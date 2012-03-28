package Setup::File::Symlink;

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

our $VERSION = '0.14'; # VERSION

our %SPEC;

$SPEC{setup_symlink} = {
    summary  => "Setup symlink (existence, target)",
    description => <<'_',

On do, will create symlink which points to specified target. If symlink already
exists but points to another target, it will be replaced with the correct
symlink if replace_symlink option is true. If a file already exists, it will be
removed (or, backed up to temporary directory) before the symlink is created, if
replace_file option is true.

If given, -undo_hint should contain {tmp_dir=>...} to specify temporary
directory to save replaced file/dir. Temporary directory defaults to ~/.setup,
it will be created if not exists.

On undo, will delete symlink if it was created by this function, and restore the
original symlink/file/dir if it was replaced during do.

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
    my $steps;
    if ($undo_action eq 'undo') {
        $steps = $args{-undo_data} or return [400, "Please supply -undo_data"];
    } else {
        $steps = [];
        if ($exists && !$is_symlink) {
            $log->infof("nok: $symlink exists but not a symlink");
            if ($is_dir) {
                if (!$replace_dir) {
                    return [412, "must replace dir but instructed not to"];
                }
                push @$steps, ["rm_r"], ["ln"];
            } else {
                if (!$replace_file) {
                    return [412, "must replace file but instructed not to"];
                }
                push @$steps, ["rm_r"], ["ln"];
            }
        } elsif ($is_symlink && $cur_target ne $target) {
            $log->infof("nok: $symlink doesn't point to correct target");
            if (!$replace_sym) {
                return [412, "must replace symlink but instructed not to"];
            }
            push @$steps, ["rmsym"], ["ln"];
        } elsif (!$exists) {
            $log->infof("nok: $symlink doesn't exist");
            if (!$create) {
                return [412, "must create symlink but instructed not to"];
            }
            push @$steps, ["ln"];
        }
    }

    return [400, "Invalid steps, must be an array"]
        unless $steps && ref($steps) eq 'ARRAY';
    return [200, "Dry run"] if $dry_run && @$steps;

    # create tmp dir for undo
    my $save_undo    = $undo_action ? 1:0;
    my $undo_hint = $args{-undo_hint} // {};
    return [400, "Invalid -undo_hint, please supply a hashref"]
        unless ref($undo_hint) eq 'HASH';
    my $tmp_dir = $undo_hint->{tmp_dir} // "$ENV{HOME}/.setup";
    if ($save_undo && !(-d $tmp_dir) && !$dry_run) {
        mkdir $tmp_dir or return [500, "Can't make temp dir `$tmp_dir`: $!"];
    }
    my $save_path = "$tmp_dir/".UUID::Random::generate;

    # perform the steps
    my $rollback;
    my $undo_steps = [];
  STEP:
    for my $i (0..@$steps-1) {
        my $step = $steps->[$i];
        $log->tracef("step %d of 0..%d: %s", $i, @$steps-1, $step);
        my $err;
        return [400, "Invalid step (not array)"] unless ref($step) eq 'ARRAY';
        if ($step->[0] eq 'rmsym') {
            $log->info("Removing symlink $symlink ...");
            if ((-l $symlink) || (-e _)) {
                my $t = readlink($symlink) // "";
                if (unlink $symlink) {
                    unshift @$undo_steps, ["ln", $t];
                } else {
                    $err = "Can't remove $symlink: $!";
                }
            }
        } elsif ($step->[0] eq 'rm_r') {
            $log->info("Removing file/dir $symlink ...");
            if ((-l $symlink) || (-e _)) {
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
            }
        } elsif ($step->[0] eq 'restore') {
            $log->info("Restoring from $step->[1] -> $symlink ...");
            if ((-l $symlink) || (-e _)) {
                $err = "Can't restore $step->[1] -> $symlink: already exists";
            } elsif (rmove $step->[1], $symlink) {
                unshift @$undo_steps, ["rm_r"];
            } else {
                $err = "Can't restore $step->[1] -> $symlink: $!";
            }
        } elsif ($step->[0] eq 'ln') {
            my $t = $step->[1] // $target;
            $log->info("Creating symlink $symlink -> $t ...");
            unless ((-l $symlink) && readlink($symlink) eq $t) {
                if (symlink $t, $symlink) {
                    unshift @$undo_steps, ["rmsym"];
                } else {
                    $err = "Can't symlink $symlink -> $t: $!";
                }
            }
        } else {
            die "BUG: Unknown step command: $step->[0]";
        }
        if ($err) {
            if ($rollback) {
                die "Failed rollback step $i of 0..".(@$steps-1).": $err";
            } else {
                $log->tracef("Step failed: $err, performing rollback ...");
                $rollback = $err;
                $steps = $undo_steps;
                goto STEP; # perform steps all over again
            }
        }
    }
    return [500, "Error (rollbacked): $rollback"] if $rollback;

    my $meta = {};
    $meta->{undo_data} = $undo_steps if $save_undo;
    $log->tracef("meta: %s", $meta);
    return [@$steps ? 200 : 304, @$steps ? "OK" : "Nothing done", undef, $meta];
}

1;
# ABSTRACT: Setup symlink (existence, target)


__END__
=pod

=head1 NAME

Setup::File::Symlink - Setup symlink (existence, target)

=head1 VERSION

version 0.14

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

=head1 DESCRIPTION

This module provides one function B<setup_symlink>.

This module is part of the Setup modules family.

This module uses L<Log::Any> logging framework.

This module has L<Rinci> metadata.

=head1 THE SETUP MODULES FAMILY

I use the C<Setup::> namespace for the Setup modules family. See L<Setup::File>
for more details on the goals, characteristics, and implementation of Setup
modules family.

=head1 SEE ALSO

Other modules in Setup:: namespace.

=head1 FUNCTIONS


=head2 setup_symlink(%args) -> [status, msg, result, meta]

Setup symlink (existence, target).

On do, will create symlink which points to specified target. If symlink already
exists but points to another target, it will be replaced with the correct
symlink if replaceB<symlink option is true. If a file already exists, it will be
removed (or, backed up to temporary directory) before the symlink is created, if
replace>file option is true.

If given, -undoB<hint should contain {tmp>dir=>...} to specify temporary
directory to save replaced file/dir. Temporary directory defaults to ~/.setup,
it will be created if not exists.

On undo, will delete symlink if it was created by this function, and restore the
original symlink/file/dir if it was replaced during do.

Arguments ('*' denotes required arguments):

=over 4

=item * B<create>* => I<bool> (default: 1)

Create if symlink doesn't exist.

If set to false, then setup will fail (412) if this condition is encountered.

=item * B<replace_dir>* => I<bool> (default: 0)

Replace if there is existing dir.

If set to false, then setup will fail (412) if this condition is encountered.

=item * B<replace_file>* => I<bool> (default: 0)

Replace if there is existing non-symlink file.

If set to false, then setup will fail (412) if this condition is encountered.

=item * B<replace_symlink>* => I<bool> (default: 1)

Replace previous symlink if it already exists but doesn't point to the wanted target.

If set to false, then setup will fail (412) if this condition is encountered.

=item * B<symlink>* => I<str>

Path to symlink.

Symlink path needs to be absolute so it's normalized.

=item * B<target>* => I<str>

Target path of symlink.

=back

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

