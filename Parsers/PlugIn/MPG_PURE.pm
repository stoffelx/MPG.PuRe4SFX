#lookup plug-in for MPG.PuRe - V0.1 - (ch) 2025-03-17
package Parsers::PlugIn::MPG_PURE;

use base qw(Parsers::PlugIn);
use SFXMenu::Debug qw(debug error);
use Manager::Config;
use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request;
use JSON;
use Data::Dumper;


sub lookup {
        my ($self,$ctx_obj)     = @_;

        # read attributes from context object
        my $author =     $ctx_obj->get('rft.creator');
        my $title  =     $ctx_obj->get('rft.title');
        my $inst   =     $ctx_obj->{'@req.institutes'}->[0] || '';

#########if-loop ggf. wieder entfernen - implementiert für Testzwecke
        if (!$inst) {
            my $inst   =     $ctx_obj->get('sfx.institute');
            }

        # read params from config file
        my $config_file         = "mpg_pure.config";
        my $config_parser       = new Manager::Config(file=>$config_file);
        my $host                = $config_parser->getSection('host','url');


        my $requestaudience = '';
        if ($inst) {
            $requestaudience = $config_parser->getSection('audience', $inst);
            }

        $author =~ s/,.*//g;

        debug "PURE_INSTITUTE is: $inst";
        debug "PURE_AUDIENCE is: $requestaudience";


####################################################################################################################
#JSON query object config                                                                                          #
####################################################################################################################
        my $header = [
            'Content-Type' => 'application/json'
            ];

        my $queryobject = "{\"query\":{\"bool\":{\"must\":[{\"term\":{\"publicState\":{\"value\":\"RELEASED\"}}},{\"term\":{\"versionState\":{\"value\":\"RELEASED\"}}},{\"bool\":{\"must\":          [{\"bool\":{\"must\":[{\"bool\":{\"should\":[{\"match\":{\"metadata.title\":{\"operator\":\"and\",\"query\":\"" . $title . "\"}}},{\"match\":{\"metadata.alternativeTitles.value\":{\"operator\":     \"and\",\"query\":\"" . $title . "\"}}}]}},{\"multi_match\":{\"fields\":[\"metadata.creators.person.familyName\",\"metadata.creators.person.givenName\"],\"operator\":\"and\",\"query\":\"" .         $author . "\",\"type\":\"cross_fields\"}}]}},{\"bool\":{\"should\":[{\"nested\":{\"path\":\"files\",\"query\":{\"bool\":{\"must\":[{\"term\":{\"files.storage\":{\"value\":\"INTERNAL_MANAGED\"}}},   {\"bool\":{\"should\":[{\"term\":{\"files.visibility\":{\"value\":\"AUDIENCE\"}}},{\"term\":{\"files.visibility\":{\"value\":\"PUBLIC\"}}}]}}]}},\"score_mode\":\"avg\"}},{\"nested\":{\"path\":      \"files\",\"query\":{\"bool\":{\"must\":[{\"term\":{\"files.storage\":{\"value\":\"EXTERNAL_URL\"}}}]}},\"score_mode\":\"avg\"}}]}}]}}]}}}";

        my $ua = LWP::UserAgent->new();
        my $purerequest = HTTP::Request->new('POST', $host, $header, $queryobject);
        my $pureresponse = $ua->request($purerequest);
        my $responsejson = $pureresponse->content;

        my $json = JSON->new;
        my $output = $json->decode($responsejson);

        debug $output;


#####################################################################################################################
#parse file delivery data from response object                                                                      #
#####################################################################################################################
        my @filecollection = ();
        my %filedata;
        my @audiences = ();

        foreach my $responserecord (@{$output->{records}}) {
            foreach my $responsefile (@{$responserecord->{data}->{files}}) {
                unless ($responsefile->{visibility} eq 'PRIVATE') {
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

                    push @filecollection, {%filedata};
                }
            }
        }

####################################################################################################################
#Iterate @filecollection data for preferred delivery                                                               #
####################################################################################################################

        my ($preferredmatch) = grep {$_->{'availability'} eq 'PUBLIC' && $_->{'contenttype'} eq 'publisher-version'} @filecollection;

        if (!$preferredmatch) {
            ($preferredmatch) = grep {$_->{'availability'} eq 'PUBLIC' && $_->{'contenttype'} eq 'any-fulltext'} @filecollection;
            }

        if (!$preferredmatch) {
            ($preferredmatch) = grep {$_->{'availability'} eq 'PUBLIC' && $_->{'contenttype'} eq 'post-print'} @filecollection;
            }

        if (!$preferredmatch && $requestaudience) {
            ($preferredmatch) = grep {
                my $filedata = $_;
                grep { $_ eq $requestaudience || $_ eq 'mpg'} @{ $filedata->{'audience'} };
                    } @filecollection
                && grep {$_->{'availability'} eq 'AUDIENCE' && $_->{'contenttype'} eq 'any-fulltext'
                    } @filecollection;
            }

        if (!$preferredmatch && $requestaudience) {
            ($preferredmatch) = grep {
                my $filedata = $_;
                grep { $_ eq $requestaudience || $_ eq 'mpg'} @{ $filedata->{'audience'} };
                    } @filecollection
                && grep {$_->{'availability'} eq 'AUDIENCE' && $_->{'contenttype'} eq 'publisher-version'
                    } @filecollection;
            }

        if (!$preferredmatch) {
            ($preferredmatch) = grep {$_->{'availability'} eq 'PUBLIC' && $_->{'contenttype'} eq 'pre-print'} @filecollection;
            }

        if (!$preferredmatch && $requestaudience) {
            ($preferredmatch) = grep {
                my $filedata = $_;
                grep { $_ eq $requestaudience || $_ eq 'mpg'} @{ $filedata->{'audience'} };
                    } @filecollection
                && grep {$_->{'availability'} eq 'AUDIENCE' && $_->{'contenttype'} eq 'post-print'
                    } @filecollection;
            }

        if (!$preferredmatch && $requestaudience) {
            ($preferredmatch) = grep {
                my $filedata = $_;
                grep { $_ eq $requestaudience || $_ eq 'mpg'} @{ $filedata->{'audience'} };
                    } @filecollection
                && grep {$_->{'availability'} eq 'AUDIENCE' && $_->{'contenttype'} eq 'pre-print'
                    } @filecollection;
            }

####################################################################################################################
#assess lookup success / failure                                                                                   #
####################################################################################################################

        unless (!$preferredmatch) {
            debug Dumper($preferredmatch);
            return 1;
            } else {
            debug "NO PURE-PlugIn preferred URL retrievable";
            return 0;
        }

}
1;
