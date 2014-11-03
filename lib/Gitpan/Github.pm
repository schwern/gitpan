package Gitpan::Github;

use Gitpan::perl5i;

use Gitpan::OO;
use Gitpan::Types;
use Pithub;

extends 'Net::GitHub::V3';
with 'Gitpan::Role::HasConfig', 'Gitpan::Role::CanBackoff';

use Encode;

haz pithub =>
  is            => 'ro',
  isa           => InstanceOf['Pithub'],
  lazy          => 1,
  default       => method {
      return Pithub->new(
          user                  => $self->owner,
          repo                  => $self->repo_name_on_github,
          token                 => $self->access_token,
          per_page              => 100,
          auto_pagination       => 1,
      );
  };

method distname { return $self->repo }
with "Gitpan::Role::CanDistLog";

haz "repo" =>
  required      => 1;

haz "repo_name_on_github" =>
  is            => 'ro',
  isa           => Str,
  lazy          => 1,
  default       => method {
      my $repo = $self->repo;

      # Github doesn't like non alphanumerics as repository names.
      # Dots seem ok.
      $repo =~ s{[^a-z0-9-_.]+}{-}ig;

      return $repo;
  };

haz "owner" =>
  is            => 'ro',
  isa           => Str,
  lazy          => 1,
  default       => method {
      return $self->config->github_owner;
  };

haz '+access_token' =>
  lazy          => 1,
  default       => method {
      return $self->config->github_access_token;
  };

haz "remote_host" =>
  is            => 'rw',
  isa           => Str,
  lazy          => 1,
  default       => method {
      return $self->config->github_remote_host;
  };

haz "_exists_on_github_cache" =>
  is            => 'rw',
  isa           => Bool,
  default       => 0;

# BUILD in Moo roles don't appear to stack nicely, so we
# go around it.
after BUILD => method(...) {
    if( $self->owner && $self->repo ) {
        $self->set_default_user_repo($self->owner, $self->repo);
    }

    return;
};

method get_repo_info() {
    my $repo           = $self->repo;
    my $repo_on_github = $self->repo_name_on_github;

    $self->dist_log( "Getting Github repo info for $repo as $repo_on_github" );

    my $result  = $self->pithub->repos->get;

    return if $result->response->code == 404;

    return $result->content if $result->success;

    croak "Error retrieving repo info about @{[$self->owner]}/$repo_on_github: ".$result->response->mo->as_json;

    return;
}

method is_empty() {
    my $result = $self->pithub->repos->commits(per_page => 1)->list;

    croak $self->repo_name_on_github." does not exist"
      if $result->response->code == 404;

    return $result->count ? 0 : 1;
}

method exists_on_github {
    $self->dist_log( "Checking if @{[ $self->repo ]} exists on Github" );

    return 1 if $self->_exists_on_github_cache;

    my $info = $self->get_repo_info;
    $self->_exists_on_github_cache(1) if $info;

    return $info ? 1 : 0;
}

method create_repo(
    :$desc      //= "Read-only release history for @{[$self->repo]}",
    :$homepage  //= "http://metacpan.org/release/@{[$self->repo]}"
)
{
    my $repo = $self->repo;

    $self->dist_log( "Creating Github repo for $repo" );

    my $result = $self->pithub->repos->create(
        org     => $self->owner,
        data    => {
            name            => encode_utf8($repo),
            description     => encode_utf8($desc),
            homepage        => encode_utf8($homepage),
            has_issues      => 0,
            has_wiki        => 0,
        }
    );

    $self->_exists_on_github_cache(1);

    return $result;
}

method maybe_create(
    Str :$desc,
    Str :$homepage
)
{
    my $repo = $self->repo;

    return $repo if $self->exists_on_github;
    return $self->create_repo(
        desc        => $desc,
        homepage    => $homepage,
    );
}

method delete_repo_if_exists() {
    return if !$self->exists_on_github;
    return $self->delete_repo;
}

method default_success_check($return?) {
    return $return ? 1 : 0;
}

method delete_repo() {
    my $repo           = $self->repo;
    my $repo_on_github = $self->repo_name_on_github;

    $self->dist_log( "Deleting $repo on Github as $repo_on_github" );

    my $result = $self->do_with_backoff(
        code  => sub {
            $self->pithub->repos->delete;
        },
        check => method($result) {
            return 1 if $result->success;

            my $code = $result->response->code;
            if( $code == 404 ) {
                $self->dist_log( "Github $repo_on_github not found" );
            }
            else {
                my $message = $result->content->{message};
                $self->dist_log( "Error deleting $repo_on_github, HTTP $code: $message" );
            }
            return 0;
        }
    );
    croak "Could not delete repository" unless $result->success;

    $self->_exists_on_github_cache(0);

    return;
}

method branch_info(
    Str :$branch //= 'master'
) {
    my $info = $self->do_with_backoff(
        times   => 6,
        code    => sub {
            $self->dist_log("Trying to get info for $branch");
            my $ret = eval {
                $self->repos->branch($branch);
            };
            if( !$ret ) {
                $self->dist_log("Attempt to get branch info for $branch failed: $@");
                croak $@ unless $@ =~ /Branch not found/;
            }

            return $ret;
        }
    );

    croak "Could not get the Github branch info for $branch: $@" if !$info;

    return $info;
}

method remote() {
    my $owner = $self->owner;
    my $repo  = $self->repo_name_on_github;
    my $token = $self->access_token;
    my $host  = $self->remote_host;

    return qq[https://$token:\@$host/$owner/$repo.git];
}

method change_repo_info(%changes) {
    return 1 unless keys %changes;

    my $repo = $self->repo_name_on_github;

    my $log_changes = join ", ", map { "$_ => $changes{$_}" } keys %changes;
    $log_changes =~ s{\n}{\\n}g;
    $self->dist_log( "Changing @{[$self->repo]} (as $repo) info: $log_changes" );

    return $self->repos->get($self->owner, $repo)->update(
        \%changes,
    );
}
