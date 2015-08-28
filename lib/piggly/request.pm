#!/usr/bin/perl

package piggly::request;

use piggly::session;
use piggly::cookie;

use strict;
use warnings;

use POSIX 'setsid'; 
use JSON;
use Data::Dumper;
use Digest::MD5 'md5_hex';

$SIG{CHLD} = 'IGNORE';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    
    my ($piggly, $req, $env) = @_;
    
    my $self  = {
        __piggly_app => $piggly,
        __psgi_req   => $req,
        __psgi_env   => $env,
        __method     => "",
        __path       => "",
        __route      => "",
        __error      => undef,
        __form       => {},
        __uploads    => {},
        __cookies    => undef,        
        __session_id => "",
        __session    => {},
        __json       => 0,
        __broken     => 0,
    };
        
    bless $self, $class;
    $self->__init;
    return $self;
}

sub err     { return shift->{"__error"}  }
sub route   { return shift->{"__route"}  }
sub path    { return shift->{"__path"}   }
sub method  { return shift->{"__method"} }
sub params  { return form(@_)          }
sub form    { return shift->{"__form"} }
sub uploads { return shift->{"__uploads"} }
sub cry {
    my $self = shift;
    my $err  = shift || "";
    $self->{"__error"} = $err;
    return 0;
}
sub cookies    { return shift->{"__cookies"}    } # cookies object
sub session    { return shift->{"__session"}    } # session object
sub session_id { return shift->{"__session_id"} }
sub is_json    { return shift->{"__json"}       }
sub broken     {
    my $self = shift;
    my $val  = shift;
    if (defined($val)) {
        $self->{"__broken"} = $val;
    }
    return $self->{"__broken"};
}

sub __init {
    my $self = shift;
    
    # Get method / path / route
    my $path     = $self->{"__psgi_req"}->path;
    my $uri_base = $self->{"__piggly_app"}->{"uri_base"};
    my $method   = lc($self->{"__psgi_env"}->{"REQUEST_METHOD"}) || "get";
    
    if ($uri_base && $path !~ m{$uri_base}) {
        # This is a problem.
        $self->cry("Error 400: Invalid request. Invalid route for this application. got \"$path\", was expecting \"$uri_base/*\"");
        $self->broken(1);
    }
    
    $path =~ s/\/+$//g;
    $path =~ s/^$uri_base//;
    $path ||= "/";

    $self->{"__method"} = $method;
    $self->{"__path"}   = lc($path);

    $self->{"__route"}  = join(" ", $method, $path);
    
    if ($self->{"__psgi_req"}->content_type && $self->{"__psgi_req"}->content_type =~ /json/i) {
        # Get JSON
        $self->{"__json"} = 1;
        my $body = $self->{"__psgi_req"}->content;
        my $perl = {};
        if ($body) {
            eval { $perl = from_json($body) };
            if ($@) {
                $self->{"__error"} = $@;
            }
            else {
                $self->{"__form"} = (ref($perl) eq "HASH")  ? Hash::MultiValue->new(%$perl) : Hash::MultiValue->new(data => $perl);
            }
        }
        
    } else {
        # Get parameters
        $self->{"__form"} = $self->{"__psgi_req"}->parameters;
        
        # Get uploads
        $self->{"__uploads"} = $self->{"__psgi_req"}->uploads;
    }
    
    # Get cookies
    my $cookies = $self->{"__psgi_req"}->cookies || {};
    $self->{"__cookies"} = piggly::cookies->new($cookies);
    
    # get session id (from a cookie if valid, otherise make a new one)
    my $session_name = $self->{"__piggly_app"}->{"session_name"};
    my $tmp          = $self->cookies->get($session_name);
    my $session_id   = "";

    if ($tmp) {
        my $session_secret = $self->{"__piggly_app"}->{"session_secret"};
        my ($id, $sig)     = split(/__/, $tmp);
        $session_id = $id if ($sig eq md5_hex(join("", $id, $session_secret)));
    }
    # Session invalid or corrupt - make a new one
    unless ($session_id) {
        my @chars = ("A".."Z", "a".."z");
        $session_id .= $chars[rand @chars] for 1..32;
    }    
    $self->{"__session_id"} = $session_id;
        
    # Build session
    $self->{"__session"} = piggly::session->new($self->{"__session_id"}, $self->{"__piggly_app"}->{"session_engine"});
    # cache session, if any
    $self->{"__session"}->get;        
}

sub __before_response {
    my $self    = shift;
    my $res     = shift;
    
    # Write the session-id to a cookie if needed.
    my $session_name      = $self->{"__piggly_app"}->{"session_name"};
    my $cur_session_value = $self->cookies->get($session_name) || "";
    my $needs_session     = 0;

    if ($cur_session_value) {
        my ($id, $sig) = split(/__/, $cur_session_value);
        if ($id ne $self->{"__session_id"}) {
            # session ID has changed, or has become invalid
            $needs_session = 1;
        }
    } else {
        $needs_session = 1;
    }
    
    if ($needs_session) {
        my $session_secret = $self->{"__piggly_app"}->{"session_secret"};
        my $session_sig    = md5_hex(join("", $self->{"__session_id"}, $session_secret));
        $self->cookies->set($session_name => join("__", $self->{"__session_id"}, $session_sig));
    }
    
    # Commit new cookies
    my $unsaved = $self->cookies->unsaved || {};
    map { $res->cookies->{$_} = $unsaved->{$_} } keys(%$unsaved);
        
    # Commit current session to persistent storage.
    $self->session->save;
}

sub template {
    my $self = shift;
    my $template_name = shift || "";
    my $data = shift || {};
    my $code = shift || 200;
    
    die "cannot operate without a template name" unless $template_name;
            
    my $res = $self->{"__psgi_req"}->new_response($code);
    $self->__before_response($res);
    
    if ($data->{"cookies"} && ref($data->{"cookies"}) eq "HASH") {
        foreach my $cookie (keys(%{ $data->{"cookies"} })) {
            $res->cookies->{$cookie} = $data->{"cookies"}->{$cookie};
        }
    }
    
    my $template_env = {
        form         => $self->form,
        route        => $self->route,
        method       => $self->method,
        path         => $self->path,
        config       => $self->{"__piggly_app"}->config,
        uri_base     => $self->{"__piggly_app"}->{"uri_base"},
        session_id   => $self->session->id,
        session      => $self->session->get,
        current_year => sprintf("%d", (localtime())[5]+1900),
        piggly_head => sub { $self->boilerplate("head") },
        piggly_body => sub { $self->boilerplate("body") }, 

    };
    
    foreach my $itm (keys($data)) {
        if ($template_env->{$itm}) {
            $self->cry("'$itm' is a core template variable. cannot re-define it");
            next;
        }
        $template_env->{$itm} = $data->{$itm};
    }
    
    my $frag   = "";
    my $procok = 0;
    my $tp     = $self->{"__piggly_app"}->{"template_engine"};
    
    $template_name .= ".tt" unless (substr($template_name, -3) eq ".tt");
    
    eval {
        $procok = $tp->process($template_name, $template_env, \$frag);
    };
    if ($@ || !$procok) {
        die join(" ", "Template processing error.", $@, $tp->error);
    }
               
    $res->content_type('text/html');
    $res->body($frag);
    return $res;
}

sub redir {
    my $self    = shift;
    my $url     = shift;        
    my $code    = shift || 301;
    
    my $res = $self->{"__psgi_req"}->new_response($code);
    
    if ($url !~ /^http/i) {
        $url = join("", $self->{"__piggly_app"}->{"uri_base"}, $url);
    }
    
    $self->__before_response($res);
    
    $res->redirect($url, $code);
    return $res;    
}

sub json {
    my $self = shift;
    my $data = shift || {};
    my $code = shift || 200;
    
    my $json_str = "";
    eval {
        $json_str = to_json($data);
    };
    die "Failed json encoding: $@" if $@;
    
    my $res = $self->{"__psgi_req"}->new_response($code);
    $self->__before_response($res);

    $res->content_type('application/json');
    $res->body($json_str);
    
    return $res;
}

sub spork {
    my $self     = shift;
    my $child_cb = shift;
    
    my $pid = fork();
    
    return 0    unless defined $pid; # failed to fork
    return $pid if $pid;             # succeeded
    
    # Child code:
    sleep 1;
    setsid();        
    exit 1 unless $child_cb;        
    exit $child_cb->();                           
}

1;
