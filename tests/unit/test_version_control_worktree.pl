#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

binmode(STDOUT, ':encoding(UTF-8)');
binmode(STDERR, ':encoding(UTF-8)');

=head1 NAME

test_version_control_worktree.pl - Unit tests for VersionControl worktree operation

=head1 DESCRIPTION

Tests the git worktree operations (list, add, remove, prune) in VersionControl tool.

=cut

use Test::More;
use File::Temp qw(tempdir);
use Cwd qw(getcwd abs_path);

# Test 1: Module loads
BEGIN { use_ok('CLIO::Tools::VersionControl') or BAIL_OUT("Cannot load VersionControl"); }

print "\n=== VersionControl Worktree Tests ===\n\n";

# Test 2: Create VersionControl instance
my $vc = CLIO::Tools::VersionControl->new(debug => 0);
ok($vc, 'VersionControl object created');
isa_ok($vc, 'CLIO::Tools::VersionControl');

# Test 3: worktree is in supported_operations
my @ops = @{$vc->{supported_operations}};
ok((grep { $_ eq 'worktree' } @ops), 'worktree is in supported_operations');

# Test 4: get_additional_parameters includes worktree params
my $params = $vc->get_additional_parameters();
ok(exists $params->{worktree_path}, 'worktree_path parameter defined');
ok(exists $params->{create_branch}, 'create_branch parameter defined');
ok(exists $params->{force}, 'force parameter defined');

# Test 5: action parameter description includes worktree actions
like($params->{action}{description}, qr/add/, 'action description includes add');
like($params->{action}{description}, qr/remove/, 'action description includes remove');
like($params->{action}{description}, qr/prune/, 'action description includes prune');

# Test 6: route_operation routes worktree correctly
# First test with non-git-repo to verify routing reaches the git repo check
my $temp_non_git = tempdir(CLEANUP => 1);
my $result = $vc->route_operation('worktree', { repository_path => $temp_non_git }, {});
ok($result, 'route_operation returns result for worktree');
like($result->{error}, qr/Not a Git repository/, 'worktree routes through git repo check');

# Test 7-12: Set up a real git repo for functional tests
my $temp_repo = tempdir(CLEANUP => 1);
my $original_cwd = getcwd();

# Initialize a git repo
system("cd $temp_repo && git init -b main >/dev/null 2>&1");
system("cd $temp_repo && git config user.email 'test\@test.com' >/dev/null 2>&1");
system("cd $temp_repo && git config user.name 'Test User' >/dev/null 2>&1");
system("cd $temp_repo && echo 'hello' > README.md && git add . && git commit -m 'initial' >/dev/null 2>&1");

# Test 7: worktree list on a real repo
my $list_result = $vc->route_operation('worktree', {
    repository_path => $temp_repo,
    action => 'list',
}, {});
ok(!$list_result->{error}, 'worktree list succeeds on real repo');
like($list_result->{output}, qr/$temp_repo/, 'worktree list shows repo path');
is($list_result->{action}, 'list', 'worktree list metadata action is correct');

# Test 8: worktree add
my $worktree_dir = "$temp_repo/wt-test";
my $add_result = $vc->route_operation('worktree', {
    repository_path => $temp_repo,
    action => 'add',
    worktree_path => $worktree_dir,
    branch => 'test-branch',
    create_branch => 1,
}, {});
ok(!$add_result->{error}, 'worktree add succeeds') or diag("Error: " . ($add_result->{error} || ''));
ok(-d $worktree_dir, 'worktree directory was created');
is($add_result->{action}, 'add', 'worktree add metadata action is correct');
is($add_result->{worktree_path}, $worktree_dir, 'worktree add metadata path is correct');

# Test 9: worktree list now shows two worktrees
my $list_result2 = $vc->route_operation('worktree', {
    repository_path => $temp_repo,
    action => 'list',
}, {});
ok(!$list_result2->{error}, 'worktree list after add succeeds');
like($list_result2->{output}, qr/wt-test/, 'worktree list shows new worktree');

# Test 10: worktree remove
my $remove_result = $vc->route_operation('worktree', {
    repository_path => $temp_repo,
    action => 'remove',
    worktree_path => $worktree_dir,
}, {});
ok(!$remove_result->{error}, 'worktree remove succeeds') or diag("Error: " . ($remove_result->{error} || ''));
ok(! -d $worktree_dir, 'worktree directory was removed');
is($remove_result->{action}, 'remove', 'worktree remove metadata action is correct');

# Test 11: worktree prune
my $prune_result = $vc->route_operation('worktree', {
    repository_path => $temp_repo,
    action => 'prune',
}, {});
ok(!$prune_result->{error}, 'worktree prune succeeds');
is($prune_result->{action}, 'prune', 'worktree prune metadata action is correct');

# Test 12: worktree add without required worktree_path fails gracefully
my $fail_result = $vc->route_operation('worktree', {
    repository_path => $temp_repo,
    action => 'add',
}, {});
ok($fail_result->{error}, 'worktree add without path returns error');
like($fail_result->{error}, qr/Git worktree failed/, 'error message is descriptive');

# Test 13: invalid worktree action fails gracefully
my $invalid_result = $vc->route_operation('worktree', {
    repository_path => $temp_repo,
    action => 'invalid_action',
}, {});
ok($invalid_result->{error}, 'invalid worktree action returns error');
like($invalid_result->{error}, qr/Git worktree failed/, 'invalid action error is descriptive');

# Test 14: worktree add with existing branch (no create)
system("cd $temp_repo && git branch feature-existing >/dev/null 2>&1");
my $worktree_dir2 = "$temp_repo/wt-existing";
my $add_existing_result = $vc->route_operation('worktree', {
    repository_path => $temp_repo,
    action => 'add',
    worktree_path => $worktree_dir2,
    branch => 'feature-existing',
}, {});
ok(!$add_existing_result->{error}, 'worktree add with existing branch succeeds')
    or diag("Error: " . ($add_existing_result->{error} || ''));
ok(-d $worktree_dir2, 'worktree directory for existing branch created');

# Cleanup: remove worktree before temp dir cleanup
system("cd $temp_repo && git worktree remove $worktree_dir2 --force >/dev/null 2>&1");

# Ensure cwd is restored
chdir $original_cwd;

done_testing();

print "\n✓ VersionControl worktree tests PASSED\n";
