#!/usr/bin/env perl

# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2013  Victor Efimov
# http://mt-aws.com (also http://vs-dev.com) vs@vs-dev.com
# License: GPLv3
#
# This file is part of "mt-aws-glacier"
#
#    mt-aws-glacier is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt-aws-glacier is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use utf8;
use Test::More tests => 275;
use Test::Deep;
use Carp;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use Test::MockModule;
use File::Path;
use File::stat;
use Data::Dumper;
use TestUtils;

warning_fatal();


my $mtroot = get_temp_dir();


# upload_file command parsing test

my ($default_concurrency, $default_partsize) = (4, 16);

# upload-file


my %common = (
	journal => 'j',
	partsize => $default_partsize,
	concurrency => $default_concurrency,
	key=>'mykey',
	secret => 'mysecret',
	region => 'myregion',
	protocol => 'http',
	vault =>'myvault',
	config=>'glacier.cfg',
	timeout => 180,
	'journal-encoding' => 'UTF-8',
	'filenames-encoding' => 'UTF-8',
	'terminal-encoding' => 'UTF-8',
	'config-encoding' => 'UTF-8'
);

#### PASS

sub assert_passes($$%)
{
	my ($msg, $query, %result) = @_;
	fake_config sub {
		disable_validations qw/journal secret key filename dir/ => sub {
			my $res = config_create_and_parse(split(' ', $query));
			print Dumper $res->{errors} if $res->{errors};
			ok !($res->{errors}||$res->{warnings}), $msg;
			is $res->{command}, 'upload-file', $msg;
			is_deeply($res->{options}, {
				%common,
				%result
			}, $msg);
		}
	}
}

###
### filename
###

## set-rel-filename

assert_passes "should work with filename and set-rel-filename",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --filename /tmp/dir/a/myfile --set-rel-filename x/y/z!,
	'name-type' => 'rel-filename',
	relfilename => 'x/y/z',
	'data-type' => 'filename',
	'set-rel-filename' => 'x/y/z',
	filename => '/tmp/dir/a/myfile';

## dir


sub test_file_and_dir
{
	my ($msg, $dir, $filename, $expected) = @_;
	assert_passes $msg,
		qq!upload-file --config glacier.cfg --vault myvault --journal j --filename $filename --dir $dir!,
		'name-type' => 'dir',
		'data-type' => 'filename',
		relfilename => $expected,
		dir => $dir,
		filename => $filename;
}



test_file_and_dir "should work with filename and dir",
	'/tmp/dir', '/tmp/dir/a/myfile', 'a/myfile';
test_file_and_dir "should work with filename and dir when file right inside dir",
	'/tmp/dir', '/tmp/dir/myfile', 'myfile';
test_file_and_dir "should work with filename and dir when filename and dir are relative",
	"tmp/dir", "tmp/dir/a/myfile", "a/myfile";
test_file_and_dir "should work with filename and dir when file right inside dir when filename and dir are relative",
	"tmp/dir", "tmp/dir/myfile", "myfile";


##
## stdin
##

## set-rel-filename

assert_passes "should work with stdin and set-rel-filename",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin --set-rel-filename x/y/z --check-max-file-size 100!,
	'name-type' => 'rel-filename',
	'data-type' => 'stdin',
	stdin => 1,
	'check-max-file-size' => 100,
	relfilename => 'x/y/z',
	'set-rel-filename' => 'x/y/z';



#### FAIL

sub assert_fails($$%)
{
	my ($msg, $query, $novalidations, $error, %opts) = @_;
	fake_config sub {
		disable_validations qw/journal key secret/, @$novalidations => sub {
			my $res = config_create_and_parse(split(' ', $query));
			ok $res->{errors}, $msg;
			ok !defined $res->{warnings}, $msg;
			ok !defined $res->{command}, $msg;
			cmp_deeply [grep { $_->{format} eq $error } @{ $res->{errors} }], [{%opts, format => $error}], $msg;
		}
	}
}

assert_fails "filename, set-rel-filename should fail with dir",
	qq!upload-file --config glacier.cfg --vault myvault --journal j!,
	[],
	'Please specify filename or stdin';

###
### filename
###


assert_fails "filename with fail without set-rel-filename or dir",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --filename /tmp/dir/a/myfile!,
	['filename'],
	'either', a => 'set-rel-filename', b => 'dir';

## set-rel-filename

assert_fails "filename, set-rel-filename should fail with dir",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --filename /tmp/dir/a/myfile --set-rel-filename x/y/z --dir abc!,
	['filename', 'dir'],
	'mutual', a => 'set-rel-filename', b => 'dir';

for (qw!/x/y/z x/../y/z ../y x/./y!) {
assert_fails "should check set-rel-filename to be relative filename for $_",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --filename /tmp/dir/a/myfile --set-rel-filename $_!,
	['filename'],
	'require_relative_filename', a => 'set-rel-filename', value => $_;
}

## dir

assert_fails "filename with fail without set-rel-filename or dir",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --filename /tmp/dir/a/myfile --dir /tmp/notdir!,
	['filename', 'dir'],
	'filename_inside_dir', a => 'filename', b => 'dir';

assert_fails "filename with fail without set-rel-filename or dir",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --filename /tmp/dir/a/myfile --dir /tmp/dir/a/b!,
	['filename', 'dir'],
	'filename_inside_dir', a => 'filename', b => 'dir';

assert_fails "filename with fail without set-rel-filename or dir",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --filename /tmp/dir/a/myfile --dir !.("x" x 2048),
	['filename'],
	'%option a% should be less than 512 characters', a => 'dir', value => ("x" x 2048); # TODO: test also for bad filename

##
## stdin
##

assert_fails "filename, set-rel-filename should be used with stdin",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin!,
	[],
	'mandatory_with', a => 'set-rel-filename', b => 'stdin';

assert_fails "check-max-file-size should be used with stdin",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin --set-rel-filename x/y/z!,
	['dir'],
	'mandatory_with', a => 'check-max-file-size', b => 'stdin';

##
## test for check-max-file-size calculation
##

{
	for my $partsize (1, 2, 4, 8, 1024, 2048, 4096) {
		my $edge_size = $partsize * 10_000;
		for my $filesize ($edge_size + 1, $edge_size + 2, $edge_size + 100) {
			assert_fails "check-max-file-size should catch wrong partsize ($partsize, $filesize)",
				qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin --set-rel-filename x/y/z --partsize $partsize --check-max-file-size $filesize!,
				['dir'],
				'partsize_vs_maxsize', 'maxsize' => 'check-max-file-size', 'partsize' => 'partsize', 'partsizevalue' => $partsize, 'maxsizevalue' => $filesize;
		}
		for my $filesize ($edge_size - 100, $edge_size - 2, $edge_size - 1, $edge_size) {
			assert_passes "should work with filename and set-rel-filename",
				qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin --set-rel-filename x/y/z --partsize $partsize --check-max-file-size $filesize!,
				'name-type' => 'rel-filename',
				'data-type' => 'stdin',
				stdin => 1,
				'check-max-file-size' => $filesize,
				partsize => $partsize,
				relfilename => 'x/y/z',
				'set-rel-filename' => 'x/y/z';
		}
	}
}

{
	my $partsize = 4096;
	my $edge_size = $partsize * 10_000;
	for my $filesize ($edge_size + 1, $edge_size + 2, $edge_size + 100) {
		assert_fails "check-max-file-size too big ($filesize)",
			qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin --set-rel-filename x/y/z --partsize $partsize --check-max-file-size $filesize!,
			['dir'],
			'maxsize_too_big', 'a' => 'check-max-file-size', value => $filesize;
	}
}

## set-rel-filename

assert_fails "set-rel-filename and dir as mutual exclusize",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin --set-rel-filename x/y/z --dir abc --check-max-file-size 100!,
	['dir'],
	'mutual', a => 'set-rel-filename', b => 'dir';


#
# some integration testing
#

sub with_save_dir(&)
{
	my $curdir = Cwd::getcwd;
	shift->();
	chdir $curdir or confess;
}

sub with_my_dir($%)
{
	my ($d, $cb) = @_;
	my $dir = "$mtroot/$d";
	with_save_dir {
		mkpath $dir;
		chdir $dir or confess;
		$cb->($dir);
	}
}

{
	with_my_dir "d1/d2", sub {
		test_file_and_dir "should work with filename and dir when file right inside dir when filename and dir are relative",
			"..", "myfile", "d2/myfile";
		test_file_and_dir "should work with filename and dir when file right inside dir when filename and dir are relative",
			"../..", "myfile", "d1/d2/myfile";
	};
}

SKIP: {
	skip "Cannot run under root", 19 if is_posix_root;

	my $restricted_abs = "$mtroot/restricted";
	my $normal_abs = "$restricted_abs/normal";
	my $file_abs = "$normal_abs/file";


	with_my_dir "restricted/normal", sub {
		open my $f, ">", $file_abs; close $f;

		mkpath "top";

		my $file_rel = "file";
		my $normal_rel = "../normal";

		is stat($file_rel)->ino, stat($file_abs)->ino;
		is stat($normal_rel)->ino, stat($normal_abs)->ino;

		ok -f $file_rel;
		ok -f $file_abs;
		ok -d $normal_rel;
		ok -d $normal_rel;

		chmod 000, $restricted_abs;

		ok  -f $file_rel;
		ok !-f $file_abs;
		ok !-d $normal_rel;
		ok !-d $normal_rel;


		test_file_and_dir "should work with filename and dir when file right inside dir when filename and dir are relative",
			'.', $file_rel, "file";

		test_file_and_dir "should work with filename and dir when file right inside dir when filename and dir are relative",
			'top', "top/somefile", "somefile";

		test_file_and_dir "should work with filename and dir when file right inside dir when filename and dir are relative",
			'.', "top/somefile", "top/somefile";

		chmod 700, $restricted_abs;
	}
}


1;
