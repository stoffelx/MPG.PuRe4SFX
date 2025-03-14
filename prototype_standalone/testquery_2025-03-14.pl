#!/usr/bin/perl

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request;
use JSON;



####################################################################################################################
#Data::Dumper for developemental purposes                                                                          #
####################################################################################################################
use Data::Dumper;



####################################################################################################################
#title data / host for developemental purposes -> to be retrieved from context object / parse param                #
####################################################################################################################
#my $title = "Defect-Mediated Functionalization of Carbon Nanotubes as a Route to Design Single-Site Basic Heterogeneous Catalysts for Biomass Conversion"; #to be obtained from context object
#my $author = "Tessonnier"; #to be obtained from context object
my $title = "Deuterium supersaturation in low-energy plasma-loaded tungsten surfaces"; #to be obtained from context object
my $author = "Gao"; #to be obtained from context object
my $host = "https://pure.mpg.de/rest/items/search"; #to be stored in parse_param
my $requestaudience = "365"; #to be detected by plugIn, sub-routine or similar



####################################################################################################################
#JSON query object config                                                                                          #
####################################################################################################################
my $header = [
    'Content-Type' => 'application/json'
    ];

my $queryobject = "{\"query\":{\"bool\":{\"must\":[{\"term\":{\"publicState\":{\"value\":\"RELEASED\"}}},{\"term\":{\"versionState\":{\"value\":\"RELEASED\"}}},{\"bool\":{\"must\":[{\"bool\":{\"must\":[{\"bool\":{\"should\":[{\"match\":{\"metadata.title\":{\"operator\":\"and\",\"query\":\"" . $title . "\"}}},{\"match\":{\"metadata.alternativeTitles.value\":{\"operator\":\"and\",\"query\":\"" . $title . "\"}}}]}},{\"multi_match\":{\"fields\":[\"metadata.creators.person.familyName\",\"metadata.creators.person.givenName\"],\"operator\":\"and\",\"query\":\"" . $author . "\",\"type\":\"cross_fields\"}}]}},{\"bool\":{\"should\":[{\"nested\":{\"path\":\"files\",\"query\":{\"bool\":{\"must\":[{\"term\":{\"files.storage\":{\"value\":\"INTERNAL_MANAGED\"}}},{\"bool\":{\"should\":[{\"term\":{\"files.visibility\":{\"value\":\"AUDIENCE\"}}},{\"term\":{\"files.visibility\":{\"value\":\"PUBLIC\"}}}]}}]}},\"score_mode\":\"avg\"}},{\"nested\":{\"path\":\"files\",\"query\":{\"bool\":{\"must\":[{\"term\":{\"files.storage\":{\"value\":\"EXTERNAL_URL\"}}}]}},\"score_mode\":\"avg\"}}]}}]}}]}}}";

#my $curl = "curl -i -X POST -H 'Content-Type: application/json' -d " . $queryobject . " " . $host;
#system ("$curl");

my $ua = LWP::UserAgent->new();
my $purerequest = HTTP::Request->new('POST', $host, $header, $queryobject);
my $pureresponse = $ua->request($purerequest);
my $responsejson = $pureresponse->content;

#print $responsejson . "\n";

my $json = JSON->new;
my $output = $json->decode($responsejson);



#####################################################################################################################
#parse file delivery data from response object                                                                      #
#####################################################################################################################
my @filecollection = ();
my %filedata;
my @audiences = ();

foreach my $responserecord (@{$output->{records}}) {
    foreach my $responsefile (@{$responserecord->{data}->{files}}) {
        unless ($responsefile->{visibility} eq 'PRIVATE') {
#            print "Pfad: $responsefile->{content}\nTyp: $responsefile->{metadata}->{contentCategory}\nVerfügbarkeit: $responsefile->{visibility}\nDateiname: $responsefile->{name}\n\n";
            $filedata{'path'} = $responsefile->{content};
            $filedata{'contenttype'} = $responsefile->{metadata}->{contentCategory};
            $filedata{'availability'} = $responsefile->{visibility};

            unless ($responsefile->{storage} eq 'EXTERNAL_URL') {
                $filedata{'filename'} = $responsefile->{name};
                $filedata{'location'} = "INTERNAL";
                } else {
                $filedata{'location'} = "EXTERNAL";
                }

            if ($responsefile->{visibility} eq 'AUDIENCE') {
                $filedata{'audience'} = $responsefile->{allowedAudienceIds};
                }
             elsif ($responsefile->{visibility} eq 'PUBLIC') {
                delete ($filedata{'audience'});
                }

#            push @filecollection, \%filedata;
            push @filecollection, {%filedata};
        }
    }
}


print Dumper(@filecollection);

####################################################################################################################
#Iterate @filecollection data for preferred delivery                                                               #
####################################################################################################################

my ($preferredmatch) = grep {$_->{'availability'} eq 'PUBLIC' && $_->{'contenttype'} eq 'publisher-version'} @filecollection;

if (!$preferredmatch) {
    ($preferredmatch) = grep {$_->{'availability'} eq 'PUBLIC' && $_->{'contenttype'} eq 'any-fulltext'} @filecollection;
    }

if (!$preferredmatch) {
    ($preferredmatch) = grep {
        my $filedata = $_;
        grep { $_ eq $requestaudience } @{ $filedata->{'audience'} };
            } @filecollection
        && grep {$_->{'availability'} eq 'AUDIENCE' && $_->{'contenttype'} eq 'publisher-version'
            } @filecollection;
    }

if (!$preferredmatch) {
    ($preferredmatch) = grep {
        my $filedata = $_;
        grep { $_ eq $requestaudience } @{ $filedata->{'audience'} };
            } @filecollection
        && grep {$_->{'availability'} eq 'AUDIENCE' && $_->{'contenttype'} eq 'any-fulltext'
            } @filecollection;
    }
	
if (!$preferredmatch) {
    ($preferredmatch) = grep {$_->{'availability'} eq 'PUBLIC' && $_->{'contenttype'} eq 'post-print'} @filecollection;
    }

if (!$preferredmatch) {
    ($preferredmatch) = grep {
        my $filedata = $_;
        grep { $_ eq $requestaudience } @{ $filedata->{'audience'} };
            } @filecollection
        && grep {$_->{'availability'} eq 'AUDIENCE' && $_->{'contenttype'} eq 'post-print'
            } @filecollection;
    }

if (!$preferredmatch) {
    ($preferredmatch) = grep {$_->{'availability'} eq 'PUBLIC' && $_->{'contenttype'} eq 'pre-print'} @filecollection;
    }

if (!$preferredmatch) {
    ($preferredmatch) = grep {
        my $filedata = $_;
        grep { $_ eq $requestaudience } @{ $filedata->{'audience'} };
            } @filecollection
        && grep {$_->{'availability'} eq 'AUDIENCE' && $_->{'contenttype'} eq 'pre-print'
            } @filecollection;
    }



print Dumper($preferredmatch);



unless (!$preferredmatch) {
    bless $preferredmatch;
    } else {
    die "No preferred match retrievable\n";
}



if ($preferredmatch->{'location'} eq 'EXTERNAL') {
    print $preferredmatch->{'path'} . "\n";
} else {
    $host =~ s/\/rest\/items\/search//g;
    print $host . $preferredmatch->{'path'} . "\n";
}

