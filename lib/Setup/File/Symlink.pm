package Setup::File::Symlink;
BEGIN {
  $Setup::File::Symlink::VERSION = '0.04';
}
# ABSTRACT: Ensure symlink existence and target

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_symlink);

our %SPEC;

$SPEC{setup_symlink} = {
    summary  => "Create symlink or fix symlink target",
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

NOTE: Not yet implemented, so will always fail under this condition.

_
            default => 0,
        }],
        replace_dir => ['bool*' => {
            summary => "Replace if there is existing dir",
            description => <<'_',

If set to false, then setup will fail (412) if this condition is encountered.

NOTE: Not yet implemented, so will always fail under this condition.

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
    my $replace_file = $args{replace_dir} // 0;
    my $replace_dir  = $args{replace_file} // 0;
    my $replace_sym  = $args{replace_symlink} // 1;

    # check current state
    my $is_symlink = (-l $symlink); # -l performs lstat()
    my $exists     = (-e _);        # now we can use -e
    my $is_dir     = (-d _);
    my $cur_target = $is_symlink ? readlink($symlink) : "";
    my $state_ok   = $is_symlink && $cur_target eq $target;

    if ($undo_action eq 'undo') {
        return [412, "Can't undo: currently $symlink is not a symlink ".
                    "pointing to $target"] unless $state_ok;
        return [304, "dry run"] if $dry_run;
        unlink $symlink
            or return [500, "Can't undo: unlink $symlink: $!"];
        my $undo_data = $args{-undo_data};
        if ($undo_data->[0] eq 'dir') {
            # XXX mv $undo_data->[1], $symlink;
        } elsif ($undo_data->[0] eq 'file') {
            # XXX mv $undo_data->[1], $symlink;
        } elsif ($undo_data->[0] eq 'symlink') {
            $log->tracef("undo setup_symlink: restoring old symlink %s -> %s",
                         $symlink, $undo_data->[1]);
            return [304, "dry run"] if $dry_run;
            symlink $undo_data->[1], $symlink
                or return [500, "Can't undo: symlink $symlink -> $target: $!"];
        } elsif ($undo_data->[0] eq 'none') {
            $log->tracef("undo setup_symlink: deleting symlink %s", $symlink);
        } else {
            return [412, "Invalid undo data"];
        }
        return [200, "OK", undef, {}];
    }

    my $undo_hint = $args{-undo_hint};

    if ($state_ok) {
        return [304, "Already ok"];
    } elsif (!$exists) {
        return [412, "Should create but told not to"] unless $create;
        $log->tracef("setup_symlink: creating symlink %s", $symlink);
        return [304, "dry run"] if $dry_run;
        symlink $target, $symlink or return [500, "Can't symlink: $!"];
        return [200, "Created", undef, {undo_data=>['none']}];
    } elsif ($is_symlink) {
        return [412, "Should replace symlink but told not to, ".
                    "please delete $symlink manually first"]
            unless $replace_sym;
        $log->tracef("setup_symlink: replacing symlink %s", $symlink);
        return [304, "dry run"] if $dry_run;
        unlink $symlink or return [500, "Can't unlink $symlink: $!"];
        symlink $target, $symlink or return [500, "Can't symlink: $!"];
        return [200, "Replaced symlink", undef,
                {undo_data=>[symlink=>$cur_target]}];
    } elsif ($is_dir) {
        return [412, "Can't setup symlink $symlink because it is currently ".
            "a dir, please delete it manually first"];
        # XXX
    } else {
        return [412, "Can't setup symlink $symlink because it is currently ".
            "a file, please delete it manually first"];
        # XXX
    }
}

1;


=pod

=head1 NAME

Setup::File::Symlink - Ensure symlink existence and target

=head1 VERSION

version 0.04

=head1 SYNOPSIS

 use Setup::File::Symlink 'setup_symlink';

 # simple usage (doesn't save undo data)
 my $res = setup_symlink symlink => "/baz", target => "/qux";
 die unless $res->[0] == 200;

 # perform setup and save undo data (undo data should be serializable)
 my $res = setup_symlink symlink => "/foo", target => "/bar",
                         -undo_action => 'do';
 die unless $res->[0] == 200;
 my $undo_data = $res->[3]{undo_data};

 # perform undo
 my $res = setup_symlink symlink => "/symlink", target=>"/target",
                         -undo_action => "undo", -undo_data=>$undo_data;
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

=item * support dry-run (simulation) mode

=item * support undo to restore state to previous/original one

=back

=head1 FUNCTIONS

None are exported by default, but they are exportable.

=head2 setup_symlink(%args) -> [STATUS_CODE, ERR_MSG, RESULT]


Create symlink or fix symlink target.

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

NOTE: Not yet implemented, so will always fail under this condition.

=item * B<replace_file>* => I<bool> (default C<0>)

Replace if there is existing non-symlink file.

If set to false, then setup will fail (412) if this condition is encountered.

NOTE: Not yet implemented, so will always fail under this condition.

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

