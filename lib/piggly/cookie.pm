#!/usr/bin/perl -w

package piggly::cookie;
use strict;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    
    my $self = {
        __cookies     => shift || {},
        __new_cookies => {},
    };
        
    bless $self, $class;    
    return $self;
}

sub get {
    my $self = shift;
    my $key  = shift || "";
    if ($key) {
        # return the key's value, or blank, if it's null or missing
        return "" unless $self->{"__cookies"}->{$key};
        return $self->{"__cookies"}->{$key};
    }
    # return all cookies
    return $self->{"__cookies"};
}

sub set {
    my $self = shift;
    my $key  = shift || "";
    my $val  = shift || "";
    return "" unless $key;
    
    $self->{"__new_cookies"}->{$key} = $val;
    $self->{"__cookies"}->{$key}     = $val;
    
    return $val;
}

sub unsaved {
    my $self = shift;
    return $self->{"__new_cookies"};
}

1;
  
