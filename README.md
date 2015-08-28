# NAME

piggly - a straight forward PSGI web framework

# SYNOPSIS

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

# DESCRIPTION

piggly was written to be a web framework with virtually 
no learning curve.  As such, much of what this framework does is 
clearly visible, and the rest is hopefully in the least
obfuscated form possible.  

This framework doesn't attempt to save you keystrokes at all costs.  It has no
DSL of it's own, and it doesn't have a "router" of any kind built in.  You write your 
own. Every time, on purpose.  If your application has thousands of routes, and need
an optimized router, this might not be the package for you.

Note: piggly will serve static content (images, videos, js, css & downloads) from the contents of $Bin/public. Any more advanced file serving should be handled by a more elegant and dedicated system. 

# PIGGLY METHODS

## new

New takes a single hash, which can contain configuration options, a single option 
named "config" which can be an absolute or relative path to a JSON config file, 
or a mixture of both.   Options found in the JSON config file take precidence.

### Options:

- **uri\_base**

    The base uri of the application. Can be "/" or "/some-path/to-your-app"
    If your application lives at "/my-application", then that is your uri\_base.
    From within the application, if $route is "get /foo/bar", then your visitor actually 
    requested "get /my-application/foo/bar".

- **htaccess**

    Boolean.  If true, the application will attempt to write an .htaccess file 
    in $Bin/.htaccess that will map all URLs under $uri\_base to your script's 
    entrypoint.  Useful when running under FCGI.

    This often requires the script entrypoint to be run by user 'root' outside of 
    the webserver environment, in order to have enough priveledges to write a file.

- **session\_name**

    The name of the session cookie that visitors will automatically receive. Default is 'session'

- **session\_secret**

    This key used to sign the session id, and prevent any kind of session hijacking by brute force. 
    Should be a string of random characters. Longer is better. There's a default secret, but it's not
    excactly a secret, since everyone with this module has it.  Use your own whenever possible.

- **templates**

    This is a colon separated list of template include directories.  Relative or absolute
    paths are accepted.  Relative paths are converted to '$Bin/$path'

    Template Toolkit is the only template engine supported.

- **session\_engine**

    This can either be the session engine's name, or a session engine object.  If the name
    is given, an attempt will be made to find and create the object.

    Valid options: 
       redis: &lt;not available currently>
       etcd:  requires 'etcd\_base' uri to be specified in config
       cookie: &lt;not available currently>
       default: uses json files in /tmp

## run\_fcgi

Enter the main loop and start responding to requests under an fcgi server, like apache with mod\_fcgid

## run\_psgi

Return a code-ref that's compatible with plackup or starman.  This is typically the last thing you run in 
your psgi file.

# PIGGLY REQUEST METHODS

Most of your time will be spend with the piggly request object. It is what is passed to your
request handlers.

## template

Compose a template, and create a response, complete with headers.

Generally:

    return $req->template(<template name>, <template vars>, <status code>);

Template vars are optional, as are configvars.  Status code is optional, and will default to "200"

Usage:
    return $req->template("main", { template\_var1 => "foo", ... }, 200);

    -or-

    return $req->template("error", { error => $error, ... }, 500);

Template name must be a template file that can be found in one of the "templates" directories
specified in your config.  template\_name should not include the file extension (.tt) of the 
template file.   So, to use "../views/foo.tt", you would call $app->template("foo", {}, ..);

## json

Compose a JSON response

Generally:
    return $req->json(&lt;data vars>, &lt;status code>);

Data vars must be a hash reference. Status code is optional and will default to "200"

Usage:
    return $req->json({ item1 => "value, item2 => ... }, 200 );

## redirect

Compose a redirect response

Generally:
    return $req->redirect(&lt;new url>, &lt;status code>);

New URL must be set. It can be any valid url.  Status code is optional, and will default to "301".

Usage:
    return $req->redirect("/login", 301);

## session

Access the piggly session object.

Usage:
   $session\_engine = $req->session;

# PIGGLY SESSION METHODS

## get

Get one or all keys in the session. 

Usage:

     # get all keys
     $entire_session = $req->session->get;

     # get one key
     $itme = $req->session->get("authenticated");
     

## set

Set one key in the session

Usage:

    $req->session->set(authenticated => 1);

## save

Save the session to whatever storage backend this engine uses.

## id

Retrieve this visitors unique session id.

Usage:

    $id = $req->session->id;
