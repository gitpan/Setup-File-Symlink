#!perl

use 5.010;
use strict;
use warnings;
use Test::More 0.96;

use File::chdir;
use File::Slurp;
use File::Temp qw(tempdir);
use Setup::File::Symlink qw(setup_symlink);

plan skip_all => "symlink() not available"
    unless eval { symlink "", ""; 1 };

my $rootdir = tempdir(CLEANUP=>1);
$CWD = $rootdir;
my $undo_data;
my $redo_data;

test_setup_symlink(
    name       => "create (dry run)",
    symlink    => "/s",
    target     => "/t",
    other_args => {-dry_run=>1},
    status     => 200,
    exists     => 0,
);
test_setup_symlink(
    name       => "create",
    symlink    => "/s",
    target     => "/t",
    other_args => {},
    status     => 200,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok(!$undo_data, "no undo data");
    },
    cleanup    => 1,
);
test_setup_symlink(
    name       => "create (with undo)",
    symlink    => "/s",
    target     => "/t",
    other_args => {-undo_action=>"do"},
    status     => 200,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok($undo_data, "there is undo data");
    },
);
test_setup_symlink(
    name       => "unchanged",
    symlink    => "/s",
    target     => "/t",
    other_args => {},
    status     => 304,
);
test_setup_symlink(
    name       => "do not create",
    symlink    => "/s2",
    target     => "/t",
    other_args => {create=>0},
    status     => 412,
    exists     => 0,
);
# XXX create (undo, dry run)
test_setup_symlink(
    name       => "create (undo)",
    symlink    => "/s",
    target     => "/t",
    other_args => {-undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    exists     => 0,
    posttest   => sub {
        my $res = shift;
        $redo_data = $res->[3]{redo_data};
    }
);
test_setup_symlink(
    name       => "create (repeat undo, failed because state is ok)",
    symlink    => "/s",
    target     => "/t",
    other_args => {-undo_action=>"undo", -undo_data=>$undo_data},
    status     => 412,
    exists     => 0,
);
# XXX create (redo, dry run)
test_setup_symlink(
    name       => "create (redo)",
    symlink    => "/s",
    target     => "/t",
    other_args => {-undo_action=>"redo", -redo_data=>$redo_data},
    status     => 200,
    exists     => 1,
);

test_setup_symlink(
    name       => "replace symlink (dry run)",
    symlink    => "/s",
    target     => "/t2",
    other_args => {-dry_run=>1},
    status     => 200,
    skip_test_target => 1,
    posttest   => sub {
        my $res = shift;
        is(readlink("$rootdir/s"), "$rootdir/t", "old symlink unreplaced");
    },
);
test_setup_symlink(
    name       => "replace symlink (with undo)",
    symlink    => "/s",
    target     => "/t2",
    other_args => {-undo_action=>"do"},
    status     => 200,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
    },
);
test_setup_symlink(
    name       => "replace symlink (undo)",
    symlink    => "/s",
    target     => "/t2",
    other_args => {-undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    skip_test_target => 1,
    posttest   => sub {
        my $res = shift;
        $redo_data = $res->[3]{redo_data};
        is(readlink("$rootdir/s"), "$rootdir/t", "old symlink restored");
    },
);
test_setup_symlink(
    name       => "replace symlink (redo)",
    symlink    => "/s",
    target     => "/t2",
    other_args => {-undo_action=>"redo", -redo_data=>$redo_data},
    status     => 200,
    skip_test_target => 1,
    posttest   => sub {
        my $res = shift;
        is(readlink("$rootdir/s"), "$rootdir/t2", "new symlink restored");
    },
);
test_setup_symlink(
    name       => "do not replace symlink",
    symlink    => "/s",
    target     => "/t",
    other_args => {replace_symlink=>0},
    status     => 412,
    skip_test_target => 1,
    posttest   => sub {
        my $res = shift;
        is(readlink("$rootdir/s"), "$rootdir/t2", "old symlink unreplaced");
    },
);

# XXX replace file (dry run)
test_setup_symlink(
    name       => "replace file (with undo)",
    presetup   => sub { unlink "$rootdir/s"; write_file "$rootdir/s", "test" },
    symlink    => "/s",
    target     => "/t",
    other_args => {replace_file=>1, -undo_action=>"do"},
    status     => 200,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
    },
);
# XXX replace file (undo, dry run)
test_setup_symlink(
    name       => "replace file (undo)",
    symlink    => "/s",
    target     => "/t",
    other_args => {replace_file=>1,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    is_symlink => 0,
    posttest   => sub {
        my $res = shift;
        $redo_data = $res->[3]{redo_data};
        ok((-f "$rootdir/s"), "old file restored");
        is(read_file("$rootdir/s"), "test", "old file content restored");
    },
);
test_setup_symlink(
    name       => "do not replace file",
    symlink    => "/s",
    target     => "/t",
    other_args => {},
    status     => 412,
    is_symlink => 0,
    posttest   => sub {
        my $res = shift;
        ok((-f "$rootdir/s"), "file unreplaced");
    },
);
# XXX replace file (redo, dry run)
test_setup_symlink(
    name       => "replace file (redo)",
    symlink    => "/s",
    target     => "/t",
    other_args => {replace_file=>1,
                   -undo_action=>"redo", -redo_data=>$redo_data},
    status     => 200,
);

# XXX replace dir (dry run)
test_setup_symlink(
    name       => "replace dir (with undo)",
    presetup   => sub {
        unlink "$rootdir/s"; mkdir "$rootdir/s";
        write_file "$rootdir/s/f", "test";
    },
    symlink    => "/s",
    target     => "/t",
    other_args => {replace_dir=>1, -undo_action=>"do"},
    status     => 200,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
    },
);
# XXX replace dir (undo, dry run)
test_setup_symlink(
    name       => "replace dir (undo)",
    symlink    => "/s",
    target     => "/t",
    other_args => {replace_dir=>1,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    is_symlink => 0,
    posttest   => sub {
        my $res = shift;
        $redo_data = $res->[3]{redo_data};
        ok((-d "$rootdir/s"), "old dir restored");
        ok((-f "$rootdir/s/f"), "old dir content restored 1");
        is(read_file("$rootdir/s/f"), "test", "old dir content restored 2");
    },
);
test_setup_symlink(
    name       => "do not replace dir",
    symlink    => "/s",
    target     => "/t",
    other_args => {},
    status     => 412,
    is_symlink => 0,
    posttest   => sub {
        my $res = shift;
        ok((-d "$rootdir/s"), "dir unreplaced");
    },
);
# XXX replace dir (redo, dry run)
test_setup_symlink(
    name       => "replace dir (redo)",
    symlink    => "/s",
    target     => "/t",
    other_args => {replace_dir=>1,
                   -undo_action=>"redo", -redo_data=>$redo_data},
    status     => 200,
);

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
    my (%args) = @_;
    subtest "$args{name}" => sub {

        my $symlink = $rootdir . $args{symlink};
        my $target  = $rootdir . $args{target};
        my %setup_args = (symlink => $symlink, target => $target);
        $setup_args{-undo_hint} = {tmp_dir=>"$rootdir/undo"};
        if ($args{other_args}) {
            while (my ($k, $v) = each %{$args{other_args}}) {
                $setup_args{$k} = $v;
            }
        }

        if ($args{presetup}) {
            $args{presetup}->();
        }

        my $res;
        eval {
            $res = setup_symlink(%setup_args);
        };
        my $eval_err = $@;

        if ($args{dies}) {
            ok($eval_err, "dies");
        }
        if ($args{status}) {
            is($res->[0], $args{status}, "status $args{status}")
                or diag explain($res);
        }

        my $is_symlink = (-l $symlink);
        my $exists     = (-e _);
        my $cur_target = $is_symlink ? readlink($symlink) : "";

        my $te = $args{exists} // 1;
        if ($te) {
            ok($exists, "exists");
            if ($args{is_symlink} // 1) {
                ok($is_symlink, "is symlink");
                unless ($args{skip_test_target}) {
                    is($cur_target, $target, "target is $target");
                }
            } else {
                ok(!$is_symlink, "not symlink");
            }
        } else {
            ok(!$exists, "does not exist");
        }

        if ($args{posttest}) {
            $args{posttest}->($res);
        }

        if ($args{cleanup}) {
            unlink $symlink;
        }
    };
}
