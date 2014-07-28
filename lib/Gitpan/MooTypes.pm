package Gitpan::MooTypes;

use perl5i::2;
use Type::Library -base;
use Type::Utils -all;
BEGIN { extends "Types::Standard" }

class_type "BackPAN::Index";
class_type "Gitpan::Dist";
class_type "Gitpan::Repo";


declare "Path",
  as InstanceOf["Path::Tiny"];

coerce "Path",
  from Str,
  via {
      print "Path coercion\n";
      return $_->path;
  };


declare "AbsPath",
  as "Path",
  where { $_->is_absolute };

coerce "AbsPath",
  from "Path",
  via {
      return $_->absolute;
  };

coerce "AbsPath",
  from Str,
  via {
      return $_->path->absolute;
  };


declare "DistName",
  as Str,
  message { "A CPAN distribution name" },
  where { !/\s/ and !/::/ };


declare "ModuleName",
  as Str,
  message { "A CPAN module name " },
  where { /^[A-Za-z]+ (?: :: \w+)* /x };


declare "URI",
  as InstanceOf["URI"];

coerce "URI",
  from Str,
  via {
      require URI;
      return URI->new($_);
  };
