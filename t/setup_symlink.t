#!perl

use 5.010;
use strict;
use warnings;
use Test::More 0.96;

use File::chdir;
use File::Slurp;
use File::Temp qw(tempdir);
use Setup::File::Symlink qw(setup_symlink);
use Test::Perinci::Tx::Manager qw(test_tx_action);

plan skip_all => "symlink() not available"
    unless eval { symlink "", ""; 1 };

my $tmpdir = tempdir(CLEANUP=>1);
$CWD = $tmpdir;

test_tx_action(
    name          => "create",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s",
    },
    f             => "Setup::File::Symlink::setup_symlink",
    args          => {symlink=>"$tmpdir/s", target=>"/t"},
);
test_tx_action(
    name          => "do not create",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s",
    },
    f             => "Setup::File::Symlink::setup_symlink",
    args          => {symlink=>"$tmpdir/s", target=>"/t", create=>0},
    status        => 412,
);
test_tx_action(
    name          => "replace symlink",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s"; symlink "/t", "$tmpdir/s";
    },
    f             => "Setup::File::Symlink::setup_symlink",
    args          => {symlink=>"$tmpdir/s", target=>"/t2"},
);
test_tx_action(
    name          => "do not replace_symlink",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s"; symlink "/t", "$tmpdir/s";
    },
    f             => "Setup::File::Symlink::setup_symlink",
    args          => {symlink=>"$tmpdir/s", target=>"/t2", replace_symlink=>0},
    status        => 412,
);
test_tx_action(
    name          => "replace file",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s"; write_file("s", "");
    },
    f             => "Setup::File::Symlink::setup_symlink",
    args          => {symlink=>"$tmpdir/s", target=>"/t2", replace_file=>1},
);
test_tx_action(
    name          => "do not replace file",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s"; write_file("s", "");
    },
    f             => "Setup::File::Symlink::setup_symlink",
    args          => {symlink=>"$tmpdir/s", target=>"/t2"},
    status        => 412,
);
test_tx_action(
    name          => "replace dir",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s"; mkdir "$tmpdir/s"; write_file("$tmpdir/s/f", "");
    },
    f             => "Setup::File::Symlink::setup_symlink",
    args          => {symlink=>"$tmpdir/s", target=>"/t2", replace_dir=>1},
);
test_tx_action(
    name          => "do not replace dir",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s"; mkdir "$tmpdir/s"; write_file("$tmpdir/s/f", "");
    },
    f             => "Setup::File::Symlink::setup_symlink",
    args          => {symlink=>"$tmpdir/s", target=>"/t2"},
    status        => 412,
);

DONE_TESTING:
done_testing();
if (Test::More->builder->is_passing) {
    #diag "all tests successful, deleting test data dir";
    $CWD = "/";
} else {
    diag "there are failing tests, not deleting test data dir $tmpdir";
}
