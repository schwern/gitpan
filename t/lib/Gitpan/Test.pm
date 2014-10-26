package Gitpan::Test;

use Gitpan::perl5i;
use Gitpan::ConfigFile;

use Import::Into;

use Test::Most ();

method import($class: ...) {
    my $caller = caller;

    $ENV{GITPAN_CONFIG_DIR} //= "."->path->absolute;
    $ENV{GITPAN_TEST}       //= 1;

    Test::Most->import::into($caller);

    # Clean up and recreate the gitpan directory
    my $gitpan_dir = Gitpan::ConfigFile->new->config->gitpan_dir;
    croak "The gitpan directory used for testing ($gitpan_dir) is outside the test tree, refusing to delete it"
      if !"t"->path->subsumes($gitpan_dir);
    $gitpan_dir->remove_tree({safe => 0});
    $gitpan_dir->mkpath;

    (\&new_repo)->alias( $caller.'::new_repo' );
    (\&new_dist)->alias( $caller.'::new_dist' );
    (\&rand_distname)->alias( $caller.'::rand_distname' );

    return;
}


{
    package Gitpan::Dist::SelfDestruct;

    use Gitpan::perl5i;
    use Gitpan::OO;

    extends 'Gitpan::Dist';

    method DESTROY {
        $self->delete_repo;
    }
}


{
    package Gitpan::Repo::SelfDestruct;

    use Gitpan::perl5i;
    use Gitpan::OO;

    extends 'Gitpan::Repo';

    method DESTROY {
        $self->delete_repo;
    }
}


func rand_distname {
    my @names;

    my @letters = ("a".."z","A".."Z");
    for (0..rand(4)+1) {
        push @names, join "", map { $letters[rand @letters] } 1..rand(20);
    }

    return @names->join("-");
}


func new_dist_or_repo( $class!, %params ) {
    my $delete = 1;

    # If we're using a random dist name, no need to check
    # if it already exists.
    if( !defined $params{distname} ) {
        $params{distname} = rand_distname;
        $delete = 0;
    }

    my $obj = $class->new( %params );
    $obj->delete_repo( wait => 1 ) if $delete;

    return $obj;
}


func new_repo(...) {
    return new_dist_or_repo( "Gitpan::Repo::SelfDestruct", @_ );
}


func new_dist(%params) {
    # Normalize between name and distname
    $params{distname} = delete $params{name};
    return new_dist_or_repo( "Gitpan::Dist::SelfDestruct", %params );
}


1;
