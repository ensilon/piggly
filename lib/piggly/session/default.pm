#!/usr/bin/perl

package piggly::session::default;
use strict;
use JSON;

sub new {
    my $proto = shift;
    my $base  = shift || "/tmp";
    my $class = ref($proto) || $proto;
    
    my $self = {
        error => "",        
        base  => $base, 
    };
    
    die("cannot find session base dir '$base'") unless -d $base;
    
    bless $self, $class;
    return $self;   
}

sub cry {
    my $self = shift;
    my $err  = shift || "";
    $self->{"error"} = $err;
    return 0;
}

sub del {
    my $self       = shift;
    my $session_id = shift;
    my $full = sprintf("%s/%s", $self->{"base"}, $session_id );
    unlink($full);
}

sub put {
    my $self       = shift;
    my $session_id = shift;
    my $data       = shift;
    
    return unless $session_id;

    return $self->cry("bad session id") unless $session_id;
    my $json = "";
    eval { $json = to_json($data) };
    return $self->cry("bad json data: $@") if $@;
    
    my $full = sprintf("%s/%s", $self->{"base"}, $session_id );
    open (my $sfh, ">", $full ) || die "cannot open session '$full'";
    print $sfh $json unless $@;
    close $sfh;
    
    return $data;
}

sub get {
    my $self       = shift;
    my $session_id = shift;

    return $self->cry("bad session id") unless $session_id;
    
    my $full = sprintf("%s/%s", $self->{"base"}, $session_id );
    
    return {} unless ( -e $full );
    
    open (my $sfh, "<", $full ) || die "cannot open session '$full'";
    my $tmp = "";
    while (<$sfh>) {
        $tmp .= $_;
    }
    close $sfh;
    my $sess = {};
    eval { $sess = from_json($tmp) };
    return {} if $@;
        
    return $sess;
}

1

