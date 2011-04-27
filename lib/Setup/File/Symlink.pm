package Setup::File::Symlink;
BEGIN {
  $Setup::File::Symlink::VERSION = '0.06';
}
# ABSTRACT: Ensure symlink existence and target

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use Data::Dump::Partial qw(dumpp);
use File::Copy::Recursive qw(rmove);
use File::Path qw(remove_tree);
use UUID::Random;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_symlink);

our %SPEC;

$SPEC{setup_symlink} = {
    summary  => "Create symlink or fix symlink target",
    description => <<'_',

On do, will create symlink which points to specified target. If symlink already
exists but points to another target, it will be replaced with the correct
symlink if replace_symlink option is true. If a file already exists, it will be
removed (or, backed up to temporary directory) before the symlink is created, if
replace_file option is true.

If given, -undo_hint should contain {tmp_dir=>...} to specify temporary
directory to save replaced file/dir. Temporary directory defaults to ~/.setup,
it will be created if not exists.

On undo, will restore the original symlink/ if it was replaced during do.

_
    args     => {
        symlink => ['str*' => {
            summary => 'Path to symlink',
            description => <<'_',

Symlink path needs to be absolute so it's normalized.

_
            arg_pos => 1,
            match   => qr!^/!,
        }],
        target => ['str*' => {
            summary => 'Target path of symlink',
            arg_pos => 0,
        }],
        create => ['bool*' => {
            summary => "Create if symlink doesn't exist",
            default => 1,
            description => <<'_',

If set to false, then setup will fail (412) if this condition is encountered.

_
        }],
        replace_symlink => ['bool*' => {
            summary => "Replace previous symlink if it already exists ".
                "but doesn't point to the wanted target",
            description => <<'_',

If set to false, then setup will fail (412) if this condition is encountered.

_
            default => 1,
        }],
        replace_file => ['bool*' => {
            summary => "Replace if there is existing non-symlink file",
            description => <<'_',

If set to false, then setup will fail (412) if this condition is encountered.

_
            default => 0,
        }],
        replace_dir => ['bool*' => {
            summary => "Replace if there is existing dir",
            description => <<'_',

If set to false, then setup will fail (412) if this condition is encountered.

_
            default => 0,
        }],
    },
    features => {undo=>1, dry_run=>1},
};
sub setup_symlink {
    my %args        = @_;
    my $dry_run     = $args{-dry_run};
    my $undo_action = $args{-undo_action} // "";

    # check args
    my $symlink     = $args{symlink};
    $symlink =~ m!^/!
        or return [400, "Please specify an absolute path for symlink"];
    my $target  = $args{target};
    defined($target) or return [400, "Please specify target"];
    my $create       = $args{create} // 1;
    my $replace_file = $args{replace_file} // 0;
    my $replace_dir  = $args{replace_dir} // 0;
    my $replace_sym  = $args{replace_symlink} // 1;

    # check current state and collect steps
    my $is_symlink = (-l $symlink); # -l performs lstat()
    my $exists     = (-e _);        # now we can use -e
    my $is_dir     = (-d _);
    my $cur_target = $is_symlink ? readlink($symlink) : "";
    my $steps = [];
    if ($exists && !$is_symlink) {
        $log->tracef("nok: exist but not a symlink");
        if ($is_dir) {
            if (!$replace_dir) {
                return [412, "must replace dir but instructed not to"];
            }
            push @$steps, ["rm"], ["ln"];
        } else {
            if (!$replace_file) {
                return [412, "must replace file but instructed not to"];
            }
            push @$steps, ["rm"], ["ln"];
        }
    } elsif ($is_symlink && $cur_target ne $target) {
        $log->tracef("nok: symlink doesn't point to correct target");
        if (!$replace_sym) {
            return [412, "must replace symlink but instructed not to"];
        }
        push @$steps, ["rmsym"], ["ln"];
    } elsif (!$exists) {
        $log->tracef("nok: doesn't exist");
        if (!$create) {
            return [412, "must create symlink but instructed not to"];
        }
        push @$steps, ["ln"];
    }

    # perform the steps
    if ($undo_action eq 'undo') {
        return [412, "Can't undo: currently $symlink is not a symlink ".
                    "pointing to $target"] unless !@$steps;
        $steps = $args{-undo_data} or return [400, "Please supply -undo_data"];
    } elsif ($undo_action eq 'redo') {
        $steps = $args{-redo_data} or return [400, "Please supply -redo_data"];
    }

    return [400, "Invalid steps, must be an array"]
        unless $steps && ref($steps) eq 'ARRAY';

    return [304, "Nothing to do"] unless @$steps;
    return [200, "Dry run"] if $dry_run;

    # create tmp dir for undo
    my $save_undo    = $undo_action ? 1:0;
    my $undo_hint = $args{-undo_hint} // {};
    return [400, "Invalid -undo_hint, please supply a hashref"]
        unless ref($undo_hint) eq 'HASH';
    my $tmp_dir = $undo_hint->{tmp_dir} // "$ENV{HOME}/.setup";
    if ($save_undo && !(-d $tmp_dir)) {
        mkdir $tmp_dir or return [500, "Can't make temp dir `$tmp_dir`: $!"];
    }
    my $save_path = "$tmp_dir/".UUID::Random::generate;

    my $is_rollback;
    my $undo_steps = [];
  STEPS:
    for my $i (0..@$steps-1) {
        my $step = $steps->[$i];
        $log->tracef("step %d of 0..%d: %s", $i, @$steps-1, $step);
        my $err;
        return [400, "Invalid step (not array)"] unless ref($step) eq 'ARRAY';
        if ($step->[0] eq 'rmsym') {
            if (unlink $symlink) {
                unshift @$undo_steps, ["ln", $cur_target];
            } else {
                $err = "Can't remove $symlink: $!";
            }
        } elsif ($step->[0] eq 'rm') {
            # do not bother to save file/dir if not asked
            if ($save_undo) {
                if (rmove $symlink, $save_path) {
                    unshift @$undo_steps, ["restore", $save_path];
                } else {
                    $err = "Can't move file/dir $symlink -> $save_path: $!";
                }
            } else {
                remove_tree($symlink, {error=>\my $e});
                if (@$e) {
                    $err = "Can't remove file/dir $symlink: ".dumpp($e);
                }
            }
        } elsif ($step->[0] eq 'restore') {
            if (rmove $step->[1], $symlink) {
                unshift @$undo_steps, ["rm"];
            } else {
                $err = "Can't restore $step->[1] -> $symlink: $!";
            }
        } elsif ($step->[0] eq 'ln') {
            my $t = $step->[1] // $target;
            if (symlink $t, $symlink) {
                unshift @$undo_steps, ["rmsym"];
            } else {
                $err = "Can't symlink $symlink -> $target: $!";
            }
        } else {
            die "BUG: Unknown step command: $step->[0]";
        }
        if ($err) {
            if ($is_rollback) {
                die "Failed rollback step $i of 0..".(@$steps-1).": $err";
            } else {
                $log->tracef("Step failed: $err, performing rollback ...");
                $is_rollback++;
                $steps = $undo_steps;
                redo STEPS;
            }
        }
    }

    my $meta = {};
    if ($undo_action =~ /^(re)?do$/) { $meta->{undo_data} = $undo_steps }
    elsif ($undo_action eq 'undo')   { $meta->{redo_data} = $undo_steps }
    return [200, "OK", undef, $meta];
}

1;


=pod

=head1 NAME

Setup::File::Symlink - Ensure symlink existence and target

=head1 VERSION

version 0.06

=head1 SYNOPSIS

 use Setup::File::Symlink 'setup_symlink';

 # simple usage (doesn't save undo data)
 my $res = setup_symlink symlink => "/baz", target => "/qux";
 die unless $res->[0] == 200 || $res->[0] == 304;

 # perform setup and save undo data
 my $res = setup_symlink symlink => "/foo", target => "/bar",
                         -undo_action => 'do';
 die unless $res->[0] == 200 || $res->[0] == 304;
 my $undo_data = $res->[3]{undo_data};

 # perform undo
 my $res = setup_symlink symlink => "/symlink", target=>"/target",
                         -undo_action => "undo", -undo_data=>$undo_data;
 die unless $res->[0] == 200;
 my $redo_data = $res->[3]{redo_data};

 # perform redo
 my $res = setup_symlink symlink => "/symlink", target=>"/target",
                         -undo_action => "redo", -redo_data=>$redo_data;
 die unless $res->[0] == 200;

=head1 DESCRIPTION

This module provides one function B<setup_symlink>.

This module is part of the Setup modules family.

This module uses L<Log::Any> logging framework.

This module's functions have L<Sub::Spec> specs.

=head1 THE SETUP MODULES FAMILY

I use the C<Setup::> namespace for the Setup modules family, typically used in
installers (or other applications). The modules in Setup family have these
characteristics:

=over 4

=item * used to reach some desired state

For example, Setup::File::Symlink::setup_symlink makes sure a symlink exists to
the desired target. Setup::File::setup_file makes sure a file exists with the
correct content/ownership/permission.

=item * do nothing if desired state has been reached

Function should return 304 (nothing to do) status.

=item * support dry-run (simulation) mode

Function should return 200 on success, but change nothing.

=item * support undo to restore state to previous/original one

=back

=head1 FUNCTIONS

None are exported by default, but they are exportable.

=head2 setup_symlink(%args) -> [STATUS_CODE, ERR_MSG, RESULT]


Create symlink or fix symlink target.

On do, will create symlink which points to specified target. If symlink already
exists but points to another target, it will be replaced with the correct
symlink if replace_symlink option is true. If a file already exists, it will be
removed (or, backed up to temporary directory) before the symlink is created, if
replace_file option is true.

If given, -undo_hint should contain {tmp_dir=>...} to specify temporary
directory to save replaced file/dir. Temporary directory defaults to ~/.setup,
it will be created if not exists.

On undo, will restore the original symlink/ if it was replaced during do.

Returns a 3-element arrayref. STATUS_CODE is 200 on success, or an error code
between 3xx-5xx (just like in HTTP). ERR_MSG is a string containing error
message, RESULT is the actual result.

This function supports undo operation. See L<Sub::Spec::Clause::features> for
details on how to perform do/undo/redo.

This function supports dry-run (simulation) mode. To run in dry-run mode, add
argument C<-dry_run> => 1.

Arguments (C<*> denotes required arguments):

=over 4

=item * B<target>* => I<str>

Target path of symlink.

=item * B<symlink>* => I<str>

Path to symlink.

Symlink path needs to be absolute so it's normalized.

=item * B<create>* => I<bool> (default C<1>)

Create if symlink doesn't exist.

If set to false, then setup will fail (412) if this condition is encountered.

=item * B<replace_dir>* => I<bool> (default C<0>)

Replace if there is existing dir.

If set to false, then setup will fail (412) if this condition is encountered.

=item * B<replace_file>* => I<bool> (default C<0>)

Replace if there is existing non-symlink file.

If set to false, then setup will fail (412) if this condition is encountered.

=item * B<replace_symlink>* => I<bool> (default C<1>)

Replace previous symlink if it already exists but doesn't point to the wanted target.

If set to false, then setup will fail (412) if this condition is encountered.

=back

=head1 SEE ALSO

L<Sub::Spec>, specifically L<Sub::Spec::Clause::features> on dry-run/undo.

Other modules in Setup:: namespace.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

