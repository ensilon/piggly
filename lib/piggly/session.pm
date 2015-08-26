#!/usr/bin/perl -w

package piggly::session;
use strict;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my ($session_id, $engine) = @_;

    return undef unless $engine;

    my $self = {
        session_id   => $session_id,
        session_data => $engine->get($session_id) || {},
        engine       => $engine,
    };
        
    bless $self, $class;    
    return $self;
}

sub id   { return shift->{"session_id"}   }

sub get {
    my $self = shift;
    my $key = shift || "";    
    return $self->{"session_data"}->{$key} if $key;
    return $self->{"session_data"};
}

sub set {
    my $self = shift;
    my $key  = shift || "";
    my $val  = shift || "";
    return "" unless $key;
    $self->{"session_data"}->{$key} = $val;
    return $val;
}

sub save {
    my $self = shift;
    $self->{"session_data"} = $self->{"engine"}->put($self->id, $self->{"session_data"});
}

sub erase {
    my $self = shift;
    $self->{"session_data"} = $self->{"engine"}->del($self->id);
}

1
  
