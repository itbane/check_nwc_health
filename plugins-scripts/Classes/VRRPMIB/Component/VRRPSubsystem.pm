package Classes::VRRPMIB::Component::VRRPSubsystem;
our @ISA = qw(Monitoring::GLPlugin::SNMP::Item);
use Data::Dumper;
use strict;

sub init {
  my $self = shift;
  $self->{groups} = [];
  $self->{assoc} = ();
  if ($self->mode =~ /device::vrrp/) {
    foreach ($self->get_snmp_table_objects(
  'VRRP-MIB', 'vrrpAssoIpAddrTable')) {
      my %entry = %{$_};
      my @index = @{$entry{indices}};
      my $key = shift(@index).'.'.shift(@index);
      my $ip = join ".", @index;
      push @{$self->{assoc}{$key}}, $ip;
    }
    foreach ($self->get_snmp_table_objects(
       'VRRP-MIB', 'vrrpOperTable')) {
      my %entry = %{$_};
      my $key = $entry{indices}->[0].".".$entry{indices}->[1];
      $entry{'vrrpAssocIpAddr'} = defined $self->{assoc}{$key} ? $self->{assoc}{$key} : [];

      my $group = Classes::VRRPMIB::Component::VRRPSubsystem::Group->new(%entry);
      if ($self->filter_name($group->{name}) &&
          $group->{'vrrpOperAdminState'} eq 'up') {
        push(@{$self->{groups}}, $group);
      }
    }
  }
}

sub check {
  my $self = shift;
  $self->add_info('checking vrrp groups');
  if ($self->mode =~ /device::vrrp::list/) {
    foreach (@{$self->{groups}}) {
      $_->list();
    }
  } elsif ($self->mode =~ /device::vrrp/) {
    if (scalar (@{$self->{groups}}) == 0) {
      $self->add_unknown('no vrrp groups');
    } else {
      foreach (@{$self->{groups}}) {
        $_->check();
      }
    }
  }
}


package Classes::VRRPMIB::Component::VRRPSubsystem::Group;
our @ISA = qw(Monitoring::GLPlugin::SNMP::TableItem);
use strict;
use Data::Dumper;

sub finish {
  my $self = shift;
  my %params = @_;
  $self->{ifIndex} = $params{indices}->[0];
  $self->{vrrpGrpNumber} = $params{indices}->[1];
  $self->{name} = $self->{vrrpGrpNumber}.':'.$self->{ifIndex};
  if ($self->mode =~ /device::vrrp::state/) {
    if (! $self->opts->role()) {
      $self->opts->override_opt('role', 'master');
    }
  }
  return $self;
}

sub check {
  my $self = shift;
  if ($self->mode =~ /device::vrrp::state/) {
    $self->add_info(sprintf 'vrrp group %s (interface %s) state is %s (active router is %s)',
        $self->{vrrpGrpNumber}, $self->{ifIndex},
        $self->{vrrpOperState},
        $self->{vrrpOperMasterIpAddr});
    if ($self->opts->role() eq $self->{vrrpOperState}) {
      $self->add_ok();
    } else {
      $self->add_critical(
          sprintf 'state in group %s (interface %s) is %s instead of %s',
              $self->{vrrpGrpNumber}, $self->{ifIndex},
              $self->{vrrpOperState},
              $self->opts->role());
    }
  } elsif ($self->mode =~ /device::vrrp::failover/) {
    $self->add_info(sprintf 'vrrp group %s/%s: active node is %s',
        $self->{vrrpGrpNumber}, $self->{ifIndex},
        $self->{vrrpOperMasterIpAddr});
    if (my $laststate = $self->load_state( name => $self->{name} )) {
      if ($laststate->{state} ne $self->{vrrpOperState}) {
        $self->add_critical(sprintf 'vrrp group %s/%s: switched %s --> %s',
        $self->{vrrpGrpNumber}, $self->{ifIndex},
        $laststate->{state}, $self->{vrrpOperState});
      } elsif ($laststate->{state} !~ /^(master|backup)$/) {
        $self->add_critical(sprintf 'vrrp group %s/%s: in state %s',
        $self->{vrrpGrpNumber}, $self->{ifIndex}, $self->{vrrpOperState});
      } else {
        $self->add_ok();
      }
    } else {
      $self->add_ok('initializing....');
    }
    $self->save_state( name => $self->{name}, save => {
        state => $self->{vrrpOperState}
    });
  }
}
sub list {
  my $self = shift;
  printf "name(grp:if)=%s state=%s/%s master=%s ips=%s\n",
      $self->{name}, $self->{vrrpOperState}, $self->{vrrpOperAdminState},
      $self->{vrrpOperMasterIpAddr},
      join ",", sort @{$self->{vrrpAssocIpAddr}};
}
