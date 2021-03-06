#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Ext::Fail;

use strict;
use warnings;
use Data::Dumper;

use Rex -base;
use IPC::Lite qw($i_am_failed);
use Rex::CLI;

$Rex::TaskList::task_list = undef;
Rex::Config->set_distributor('Parallel_ForkManager');

require Exporter;
use base qw(Exporter);
use vars qw(@EXPORT);

@EXPORT = qw(fail max_fail_counter on_fail);

my $max_fail_counter = 0;
my $inside_fail      = 0;

my @fail_code = ();

Rex::CLI->add_exit(
  sub {
    if ($i_am_failed) {
      CORE::exit $i_am_failed;
    }
  }
);

sub fail(&) {
  my $code = shift;
  $inside_fail = 1;
  $i_am_failed = 0;

  my $task_code = sub {
    my @exit_codes = Rex::TaskList->create()->get_exit_codes();
    my @failed_tasks = grep { $_ > 0 } @exit_codes;

    if ( scalar @failed_tasks > $max_fail_counter ) {
      for my $fail_c (@fail_code) {
        $fail_c->( scalar(@failed_tasks) );
      }

      $i_am_failed = 1;

      die(
        "Failcounter reached. Too many tasks failed.\nFailcounter: "
          . scalar(@failed_tasks)
          . "\nMax fails: $max_fail_counter\n",
        "error"
      );
    }
  };

  my @all_tasks = Rex::TaskList->create()->get_tasks;

  for my $task (@all_tasks) {
    my $task_o = Rex::TaskList->create()->get_task($task);
    $task_o->modify( 'after_task_finished', $task_code, );
  }

  $code->();

  $inside_fail = 0;
}

sub max_fail_counter {
  if ( !$inside_fail ) {
    die
      "max_fail_counter can only be called inside fail{} block. Nested fail blocks are currently not supported.";
  }

  $max_fail_counter = shift;
}

sub on_fail(&) {
  my $code = shift;
  push @fail_code, $code;
}

1;

=pod

=head1 NAME

Rex::Ext::Fail - Fail execution if a defined number of tasks fail.

If you need to run one or more tasks on many servers and you want to stop the execution if a task fails on a specific number of systems, this module is for you.

=head1 SYNOPSIS

 use Rex::Ext::Fail;
  
 group servers => "frontend-[01..05]";
    
 task "rollout", sub {
   fail {
     max_fail_counter 2;  # fail the execution if the there are errors on 2 or more systems.
     do_task [qw/
       prepare
       deploy_app
       test_app
       switch_instance
     /];
   };
 };
   
 task "prepare", group => "servers", sub {
 };
    
 task "deploy_app", group => "servers", sub {
 };
    
 task "test_app", group => "servers", sub {
 };
    
 task "switch_instance", group => "servers", sub {
 };

