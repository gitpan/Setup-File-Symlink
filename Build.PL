
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "File::Slurp" => 0,
    "File::chdir" => 0,
    "Module::Build" => "0.3601",
    "Test::More" => "0.96",
    "Test::Perinci::Tx::Manager" => "0.30"
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Setup symlink (existence, target)",
  "dist_author" => [
    "Steven Haryanto <stevenharyanto\@gmail.com>"
  ],
  "dist_name" => "Setup-File-Symlink",
  "dist_version" => "0.23",
  "license" => "perl",
  "module_name" => "Setup::File::Symlink",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "File::Trash::Undoable" => "0.05",
    "Log::Any" => 0,
    "Rinci" => "v1.1.26",
    "Setup" => "v1.0.3",
    "perl" => "5.010000"
  },
  "script_files" => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
