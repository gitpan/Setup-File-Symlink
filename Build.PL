
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.3601"
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Setup symlink (existence, target)",
  "dist_author" => [
    "Steven Haryanto <stevenharyanto\@gmail.com>"
  ],
  "dist_name" => "Setup-File-Symlink",
  "dist_version" => "0.25",
  "license" => "perl",
  "module_name" => "Setup::File::Symlink",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "Capture::Tiny" => 0,
    "File::Trash::Undoable" => "0.06",
    "Log::Any" => 0,
    "Rinci" => "v1.1.29",
    "Setup" => "v1.0.4",
    "UUID::Random" => 0,
    "perl" => "5.010001"
  },
  "script_files" => [],
  "test_requires" => {
    "Capture::Tiny" => 0,
    "File::Slurp" => 0,
    "File::chdir" => 0,
    "Test::More" => "0.96",
    "Test::Perinci::Tx::Manager" => "0.40",
    "blib" => 0
  }
);


unless ( eval { Module::Build->VERSION(0.4004) } ) {
  my $tr = delete $module_build_args{test_requires};
  my $br = $module_build_args{build_requires};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
