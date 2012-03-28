#!perl

use 5.010;
use strict;
use warnings;
use Test::More 0.96;

use File::chdir;
use File::Slurp;
use File::Temp qw(tempdir);
use Setup::File::Symlink qw(setup_symlink);
use Test::Setup qw(test_setup);

plan skip_all => "symlink() not available"
    unless eval { symlink "", ""; 1 };

my $rootdir = tempdir(CLEANUP=>1);
$CWD = $rootdir;

test_setup_symlink(
    name          => "create",
    symlink       => "/s",
    target        => "/t",
    other_args    => {},
    check_unsetup => {exists=>0},
    check_setup   => {},
    cleanup       => sub { unlink "s" },
);
test_setup_symlink(
    name          => "do not create",
    symlink       => "/s",
    target        => "/t",
    other_args    => {create=>0},
    check_unsetup => {exists=>0},
    arg_error     => 1, # 412
);
test_setup_symlink(
    name          => "replace symlink",
    prepare       => sub { symlink "t", "s" },
    symlink       => "/s",
    target        => "/t2",
    other_args    => {},
    check_unsetup => {target=>"t"},
    check_setup   => {target=>"$rootdir/t2"},
    cleanup       => sub { unlink "s" },
);
test_setup_symlink(
    name          => "do not replace_symlink",
    prepare       => sub { symlink "t", "s" },
    symlink       => "/s",
    target        => "/t2",
    other_args    => {replace_symlink=>0},
    check_unsetup => {target=>"t"},
    arg_error     => 1, # 412
    cleanup       => sub { unlink "s" },
);
test_setup_symlink(
    name          => "replace file",
    prepare       => sub { write_file "s", "test" },
    symlink       => "/s",
    target        => "/t",
    other_args    => {replace_file=>1},
    check_unsetup => {is_symlink=>0},
    check_setup   => {target=>"$rootdir/t"},
    cleanup       => sub { unlink "s" },
);
test_setup_symlink(
    name          => "do not replace file",
    prepare       => sub { write_file "s", "test" },
    symlink       => "/s",
    target        => "/t",
    other_args    => {},
    check_unsetup => {is_symlink=>0},
    arg_error     => 1, # 412
    cleanup       => sub { unlink "s" },
);
test_setup_symlink(
    name          => "replace dir",
    prepare       => sub { mkdir "s"; write_file "s/f", "test" },
    symlink       => "/s",
    target        => "/t",
    other_args    => {replace_dir=>1},
    check_unsetup => {is_symlink=>0,
                      extra=>sub {
                          ok((-f "s/f"), "file inside dir still exists");
                          is(read_file("s/f"), "test", "file content intact");
                      }},
    check_setup   => {target=>"$rootdir/t"},
    cleanup       => sub { unlink "s" },
);
test_setup_symlink(
    name          => "do not replace dir",
    prepare       => sub { mkdir "s" },
    symlink       => "/s",
    target        => "/t",
    other_args    => {},
    check_unsetup => {is_symlink=>0},
    arg_error     => 1, # 412
    cleanup       => sub { rmdir "s" },
);
goto DONE_TESTING;

# XXX reject invalid undo data?

DONE_TESTING:
done_testing();
if (Test::More->builder->is_passing) {
    #diag "all tests successful, deleting test data dir";
    $CWD = "/";
} else {
    diag "there are failing tests, not deleting test data dir $rootdir";
}

sub test_setup_symlink {
    my (%tssargs) = @_;

    my %tsargs;

    for (qw/name arg_error set_state1 set_state2 prepare cleanup/) {
        $tsargs{$_} = $tssargs{$_};
    }
    $tsargs{function} = \&setup_symlink;

    my $symlink = $rootdir . $tssargs{symlink};
    my $target  = $rootdir . $tssargs{target};
    my %fargs = (symlink => $symlink, target => $target,
                 -undo_hint => {tmp_dir=>"$rootdir/undo"},
                 %{$tssargs{other_args} // {}},
             );
    $tsargs{args} = \%fargs;

    my $check = sub {
        my %cargs = @_;

        my $is_symlink = (-l $symlink);
        my $exists     = (-e _);
        my $cur_target = $is_symlink ? readlink($symlink) : "";

        my $te = $cargs{exists} // 1;
        if ($te) {
            ok($exists, "exists");
            if ($cargs{is_symlink} // 1) {
                ok($is_symlink, "is symlink");
                if (defined $cargs{target}) {
                    is($cur_target, $cargs{target}, "target is $cargs{target}");
                } elsif ($cargs{test_target} // 1) {
                    is($cur_target, $target, "target is $target");
                }
            } else {
                ok(!$is_symlink, "not symlink");
            }
        } else {
            ok(!$exists, "does not exist");
        }
        if ($cargs{extra}) {
            $cargs{extra}->();
        }
    };

    $tsargs{check_setup}   = sub { $check->(%{$tssargs{check_setup}}) };
    $tsargs{check_unsetup} = sub { $check->(%{$tssargs{check_unsetup}}) };
    if ($tssargs{check_state1}) {
        $tsargs{check_state1} = sub { $check->(%{$tssargs{check_state1}}) };
    }
    if ($tssargs{check_state2}) {
        $tsargs{check_state2} = sub { $check->(%{$tssargs{check_state2}}) };
    }

    test_setup(%tsargs);
}
