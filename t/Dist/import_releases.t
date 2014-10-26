#!/usr/bin/env perl

use lib 't/lib';
use Gitpan::perl5i;
use Gitpan::Test;

use Gitpan::Dist;

subtest "error handling" => sub {
    my $dist = Gitpan::Dist->new(
        name        => "Acme-LookOfDisapproval"
    );
    $dist->delete_repo;

    my $error_at = $dist->release_from_version(0.003);

    $dist->import_releases(
        before_import => method($release) {
            die "Testing error" if $release->version == $error_at->version;
        },
        push => 0,
    );

    like $dist->config->gitpan_log_file->slurp_utf8,
      qr{^Error importing @{[$error_at->short_path]}: Testing error }ms;
    like $dist->dist_log_file->slurp_utf8,
      qr{^Testing error }ms;

    cmp_deeply $dist->git->releases, [
        "ETHER/Acme-LookOfDisapproval-0.001.tar.gz",
        "ETHER/Acme-LookOfDisapproval-0.002.tar.gz",
        "ETHER/Acme-LookOfDisapproval-0.004.tar.gz",
        "ETHER/Acme-LookOfDisapproval-0.005.tar.gz",
        "ETHER/Acme-LookOfDisapproval-0.006.tar.gz",
    ], "import_releases() continues after a bad release";
};


subtest "skipping releases" => sub {
    my $dist = Gitpan::Dist->new(
        name        => "Date-Spoken-German"
    );
    $dist->delete_repo;

    # Insert a release to skip into the config.  Be sure to clear out
    # the skip release cache.  We pick this one because it is in a
    # subdirectory for extra tricks.
    $dist->config->skip->{releases}->push('CHRWIN/date-spoken-german/date-spoken-german-0.03.tar.gz');
    $dist->config->_clear_skip_releases;

    $dist->import_releases( push => 0 );

    cmp_deeply scalar $dist->git->releases->sort, [sort 
        'CHRWIN/date-spoken-german/date-spoken-german-0.02.tar.gz',
        'CHRWIN/date-spoken-german/Date-Spoken-German-0.04.tar.gz',
        'CHRWIN/date-spoken-german/Date-Spoken-German-0.05.tar.gz'
    ];
};


subtest "Distribution with no releases" => sub {
    my $dist_no_releases = Gitpan::Dist->new(
        name    => "ReForm"
    );
    $dist_no_releases->delete_repo;

    cmp_deeply $dist_no_releases->releases_to_import, [],
      "distribution has no releases";

    $dist_no_releases->import_releases;
    ok $dist_no_releases->repo->git->is_empty;
    ok !$dist_no_releases->github->exists_on_github, "did not create a Github repo";
};


subtest "Same name, different case" => sub {
    my $dist1 = Gitpan::Dist->new(
        name    => "ReForm"
    );
    $dist1->github->maybe_create;

    my $dist2 = Gitpan::Dist->new(
        name    => "reform"
    );

    ok !$dist2->import_releases;

    like $dist2->config->gitpan_log_file->slurp_utf8, qr{^Error: distribution ReForm already exists, reform would clash\.$}ms;

    # This is an awkward way of doing a case sensitive directory check
    # on a case insensitive filesystem.
    ok(
        (grep { $_ eq $dist1->name }
         map  { $_->basename }
             $dist2->repo_dir->parent->children),
        "import stopped before repo created"
   );
};


done_testing;

