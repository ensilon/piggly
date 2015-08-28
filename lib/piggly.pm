#!/usr/bin/perl

package piggly;

use strict;
use warnings;

our $VERSION = '1.00';


=head1 NAME

piggly - a straight forward PSGI web framework

=head1 SYNOPSIS

    use piggly;

    # Get config from a file
    my $p = piggly->new({ config => "../config/file.json" });

    # -or - Get config from this hash.
    my $p = piggly->new({ option => "value", option2 => ... });

    # In FCGI mode
    $p->run_fcgi(
        sub {
            # success
            my ($req, $route, $form) = @_;
        },
        sub {
            my ($req, $route, $form, $error) = @_;
        },
    );

    # In PSGI mode (e.g. under 'starman')
    $p->run_fcgi(
        sub {
            # success
            my ($req, $route, $form) = @_;
        },
        sub {
            my ($req, $route, $form, $error) = @_;
        },
    );

=head1 DESCRIPTION

piggly was written to be a web framework with virtually 
no learning curve.  As such, much of what this framework does is 
clearly visible, and the rest is hopefully in the least
obfuscated form possible.  
  
This framework doesn't attempt to save you keystrokes at all costs.  It has no
DSL of it's own, and it doesn't have a "router" of any kind built in.  You write your 
own. Every time, on purpose.  If your application has thousands of routes, and need
an optimized router, this might not be the package for you.

Note: piggly will serve static content (images, videos, js, css & downloads) from the contents of $Bin/public. Any more advanced file serving should be handled by a more elegant and dedicated system. 

=head1 PIGGLY METHODS

=head2 new

New takes a single hash, which can contain configuration options, a single option 
named "config" which can be an absolute or relative path to a JSON config file, 
or a mixture of both.   Options found in the JSON config file take precidence.

=head3 Options:

=over

=item B<uri_base>

The base uri of the application. Can be "/" or "/some-path/to-your-app"

=item B<htaccess>

Boolean.  If true, the application will attempt to write an .htaccess file 
in $Bin/.htaccess that will map all URLs under $uri_base to your script's 
entrypoint.  Useful when running under FCGI.

This often requires the script entrypoint to be run by user 'root' outside of 
the webserver environment, in order to have enough priveledges to write a file.

=item B<session_name>

The name of the session cookie that visitors will automatically receive. Default is 'session'

=item B<session_secret>

This key used to sign the session id, and prevent any kind of session hijacking by brute force. 
Should be a string of random characters. Longer is better. There's a default secret, but it's not
excactly a secret, since everyone with this module has it.  Use your own whenever possible.

=item B<templates>

This is a colon separated list of template include directories.  Relative or absolute
paths are accepted.  Relative paths are converted to '$Bin/$path'

Template Toolkit is the only template engine supported.

=item B<session_engine>

This can either be the session engine's name, or a session engine object.  If the name
is given, an attempt will be made to find and create the object.

Valid options: 
   redis: <not available currently>
   etcd:  requires 'etcd_base' uri to be specified in config
   cookie: <not available currently>
   default: uses json files in /tmp

=back

=head2 run_fcgi

Enter the main loop and start responding to requests under an fcgi server, like apache with mod_fcgid

=head2 run_psgi

Return a code-ref that's compatible with plackup or starman.  This is typically the last thing you run in 
your psgi file.

=head1 PIGGLY REQUEST METHODS

Most of your time will be spend with the piggly request object. It is what is passed to your
request handlers.

=head2 template

Compose a template, and create a response, complete with headers.

Generally:

    return $req->template(<template name>, <template vars>, <status code>);

Template vars are optional, as are configvars.  If config vars are empty or missing, the
http response status code will default to "200 ok"

Usage:
    return $req->template("main", { template_var1 => "foo", ... }, 200);

    -or-

    return $req->template("error", { error => $error, ... }, 500);

Template name must be a template file that can be found in one of the "templates" directories
specified in your config.  template_name should not include the file extension (.tt) of the 
template file.   So, to use "../views/foo.tt", you would call $app->template("foo", {}, ..);

=head2 json

Compose a JSON response

Generally:
    return $req->json(<data vars>, <config vars>);

Data vars must be a hash reference. Config vars must also be a hash reference and is optional.
If config vars are empty or missing, the http response status code will default to "200 ok"

Usage:
    return $req->json({ item1 => "value, item2 => ... }, { status => 200 });

=head2 session

Access the piggly session object.

Usage:
   $session_engine = $req->session;

=head1 PIGGLY SESSION METHODS

=head2 get

Get one or all keys in the session. 

Usage:

     # get all keys
     $entire_session = $req->session->get;

     # get one key
     $itme = $req->session->get("authenticated");
     
=head2 set

Set one key in the session

Usage:
     
    $req->session->set(authenticated => 1);

=head2 save

Save the session to whatever storage backend this engine uses.

=head2 id

Retrieve this visitors unique session id.

Usage:
   
    $id = $req->session->id;

=cut

use Data::Dumper;

use Plack::Request;
use Plack::Handler::FCGI;
use Plack::Builder;

use POSIX 'setsid';
use FindBin '$Bin';

use piggly::request;
use piggly::session;
use piggly::session::default;

use Template;
use JSON;

our $err = ""; # Suicide note.

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $config = shift;
    
    $config = {} unless ref($config) eq "HASH";
    
    __config_from_file($config);
    
    my $template_engine = __build_template_engine($config);
    my $session_engine  = __build_session_engine($config);
    
    unless ($template_engine) {
        $err = "Bad template engine! Cannot run.";
        return undef;
    }
    
    unless ($session_engine) {
        $err = "Bad session engine! Cannot run.";
        return undef;
    }
    
    my $self  = {
        config          => $config,
        uri_base        => $config->{"uri_base"}        || "",
        global          => $config->{"global"}          || {},
        broken          => $config->{"broken"}          || 0,
        broken_how      => $config->{"broken_how"}      || "",
        template_engine => $template_engine,
        session_name    => $config->{"session_name"}    || "session",
        session_secret  => $config->{"session_secret"}  || "Zbu23i-adk4i-4GEQ-annbaiep-qe43P",
        session_engine  => $session_engine,
        process_name    => $config->{"process_name"}    || "",
        default_lang    => $config->{"default_lang"}    || "en",
    };
    
    bless $self, $class;
    $self->write_htaccess if $config->{"write_htaccess"};
    return $self;
}

sub config   { return shift->{"config"}   }
sub uri_base { return shift->{"uri_base"} }

sub broken   { return shift->{"broken"}   }

sub cripple  {
    my $self = shift;
    my $how  = shift || "";
    $self->{"broken"}     = 1;
    $self->{"broken_how"} = $how;
    return 1;
}

sub heal {
    my $self = shift;
    $self->{"broken"}     = 0;
    $self->{"broken_how"} = "";
    return 1;
}

sub global {
    my $self = shift;
    my $key  = shift;
    my $val  = shift || undef;
    
    return $self->{"global_vars"} unless $key;    

    $self->{"global_vars"}->{$key} = $val if defined $val;

    return $self->{"global_vars"}->{$key} || undef;
}


sub __build_session_engine {
    my $config  = shift;
    
    return $config->{"session_engine"} if $config->{"session_engine"} && ref($config->{"session_engine"});
    
    if ($config->{"session_engine"}) {
        # We're given the name of our session engine. Let's see if we can build the object
        my $name = $config->{"session_engine"};
        my $eng  = undef;
        
        if ($name eq "etcd") {
            if ($config->{"etcd_base"}) {
                $eng = piggly::session::etcd->new($config->{"etcd_base"});
                unless ($eng) {
                    # OH shit!
                    $config->{"broken"}     = 1;
                    $config->{"broken_how"} = "Unable to initialize session engine.";
                    print STDERR "Cannot create etcd session engine. Failed\n";
                    return undef;
                }
            }
            else {
                print STDERR "Cannot create etcd session engine without etcd_base. Using default engine.\n";
                return undef;
            }
        }
        elsif ($name eq "redis") {
            # TODO
            print STDERR "Redis engine not implemented, but it's a great idea. Using default engine.\n";
            $config->{"broken"}     = 1;
            $config->{"broken_how"} = "Unable to initialize session engine (not supported)";
            return undef;
        }
        elsif ($name eq "default") {
            # no need to build anything. This will happen on its own
            return piggly::session::default->new;
        }
        else {
            print STDERR "Unknown engine '$$config{session_engine}'\n";
            $config->{"broken"}     = 1;
            $config->{"broken_how"} = "Unable to initialize session engine (unknown type)";
            return undef;
        }
    }
    elsif (! $config->{"session_engine"}) {
        return piggly::session::default->new;
    }

}

sub __build_template_engine {
    my $config  = shift;
    my %incpath = ();
    
    if ($config->{"templates"}) { # colon separated list of template include directories
        my @tmp;
        foreach my $path (split(/:/, $config->{"templates"})) {
            $path =~ s/^\s+//g;
            $path = "$Bin/$path" if $path =~ /^\./;
            push @tmp, $path;
        }
        $incpath{"INCLUDE_PATH"} = join(":", @tmp);
    }
    
    open(TM, ">/tmp/foo"); print TM Dumper \%incpath; close TM;
    
    return Template->new({ %incpath })
}

sub __config_from_file {
    my $config = shift;
    my $file;
    
    return unless $config->{"config"};
    
    $file = $config->{"config"};
    $file = sprintf("%s/%s", $Bin, $file) if $file =~ /^\./;
    unless ( -e $file ) {
        print STDERR "Config file '$file' not found\n";
        return 0;
    }
    
    my $cfgfile;
    unless (open (my $cfgfile, "<", $file)) {
        print STDERR "Cannot open $file\n";
        return 0;
    }
    
    my $json = "";
    while (<$cfgfile>) { $json .= $_ }        
    close $cfgfile;    
    unless ($json) {
        print STDERR "Config is empty\n";
        return 0;
    }
    
    my $data;
    eval { $data = from_json($json) };
    if ($@ || !$data) {
        print STDERR "Failed to parse JSON from '$file'\n";
        print STDERR "Error: $@\n" if $@;
        return 0;
    }
    
    map { $config->{$_} => $data->{$_} } keys(%$data);

    return 1;
}

# to run under psgi, simply return the coderef for the application
sub run_psgi { return get_psgi_app(@_) }

# uses plack::handler::fcgi's eventloop.  This routine never returns!
sub run_fcgi {
    my $self       = shift;
    my $success_cb = shift;
    my $fail_cb    = shift;
        
    my $app    = $self->get_psgi_app($success_cb, $fail_cb);
    my $server = Plack::Handler::FCGI->new(nproc => 5, detach => 1);
    
    $server->run($app); # forever!
}

sub get_psgi_app {
    my $self       = shift;
    my $success_cb = shift;
    my $fail_cb    = shift;
        
    my $app = sub {
        my $env       = shift;
        my $piggly    = $self;
        my $req       = Plack::Request->new($env);        
        my $path_info = $req->path_info;
        my $query     = $req->parameters->{"query"};
                
        my $piggly_request = piggly::request->new($piggly, $req, $env);
        my $response;

        if ($self->broken || $piggly_request->broken) {
            $response = $fail_cb->(
                $piggly_request,
                $piggly_request->route,
                $piggly_request->form, 
                $self->{"broken_how"} || $piggly_request->err,
            );
        }
        else {
            eval {
                $response = $success_cb->($piggly_request, $piggly_request->route, $piggly_request->form);
            };
            $response = $fail_cb->($piggly_request, $piggly_request->route, $piggly_request->form, $@) if $@;
        }
        
        unless(ref($response)) {
            # got garbage.
            $response = Plack::Response->new(500);
            $response->content_type('text/html');
            $response->body("<h1>oh no</h1>");
        }
        
        $response->finalize;
    };
    
    my $wrapped_app = builder {
        enable "Plack::Middleware::Static", 
          path => qr{^/(images|videos|js|css|downloads)/}, 
          root => "$Bin/public";
        $app;
    };        
    return $wrapped_app;
}


# Write a good .htaccess file.                                #
# Remember, apache will have to allow this override           #
sub write_htaccess {
    my $self = shift;
    my $uri_base = $self->{"uri_base"};
    
    return 1 if (-e "$Bin/.htaccess" );
    unless ($uri_base) {
        print STDERR "WARNING: printing htaccess file with no base url. use 'base_url' to set this. remove htaccess file to rebuild automatically\n";
        return 0;
    }
    
    open (my $ht, ">", "$Bin/.htaccess") || die "Cannot open $Bin/.htaccess: $!";
    print $ht htaccess($uri_base);
    close($ht);
    
    return 1;
}

sub htaccess {
    my $base = shift || "/";
    my $fn1  = $0;
    my $fn2;

    $fn1  = (split(/\//, $fn1))[-1];
    $fn2  = $fn1;
    $fn1 =~ s/\./\\\./g;

my $hta = << "EOHTA";

   <IfModule mod_rewrite.c>
      RewriteEngine On
      RewriteBase $base
      RewriteRule ^$base/$fn1\$ - [L]
      RewriteCond %{REQUEST_FILENAME} !-f
      RewriteCond %{REQUEST_FILENAME} !-d
      RewriteRule . $base/$fn2 [L]
   </IfModule>

EOHTA
return $hta;
}


1;
  
