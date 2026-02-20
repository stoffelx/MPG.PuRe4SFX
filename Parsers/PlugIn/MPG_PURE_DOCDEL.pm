#document delivery plug-in for MPG.PuRe - V0.2 - (ch) 2026-02-13
package Parsers::PlugIn::MPG_PURE_DOCDEL;

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
        my $title  =     $ctx_obj->get('rft.atitle') || $ctx_obj->get('rft.btitle');
        my $author =     ($ctx_obj->get('@rft.aulast') && $ctx_obj->get('@rft.aulast')->[0]) ? $ctx_obj->get('@rft.aulast')->[0] : '';
        my $inst   =     $ctx_obj->{'@req.institutes'}->[0] || '';
        my $pureid =     $ctx_obj->get('pureid') || '';


        # read params from config file
        my $config_file         = "mpg_pure.config";
        my $config_parser       = new Manager::Config(file=>$config_file);
        my $ihost               = $config_parser->getSection('host','item');
        my $shost               = $config_parser->getSection('host','search');

        my $requestaudience = '';
        if ($inst) {
            $requestaudience = $config_parser->getSection('audience', $inst);
            } else {
			return 0;
			}


        # author formatting for API request
        $author =~ s/,.*//g;


        # some debug for more comfortable testing
        debug "PURE_INSTITUTE is: $inst";
        debug "PURE_AUDIENCE is: $requestaudience";
        debug "PURE_ID is: $pureid";


        # data structure declaration
        my @filecollection = ();
        my %filedata;
        my @audiences = ();


        # initiate API request
        if (!$pureid) {

            my $header = [
                'Content-Type' => 'application/json'
                ];

            my $queryobject = "{\"query\":{\"bool\":{\"must\":[{\"term\":{\"publicState\":{\"value\":\"RELEASED\"}}},{\"term\":{\"versionState\":{\"value\":\"RELEASED\"}}},{\"bool\":{\"must\":      [{\"bool\":{\"must\":[{\"bool\":{\"should\":[{\"match\":{\"metadata.title\":{\"operator\":\"and\",\"query\":\"" . $title . "\"}}},{\"match\":{\"metadata.alternativeTitles.value\":{\"operator\":     \"and\",\"query\":\"" . $title . "\"}}}]}},{\"multi_match\":{\"fields\":[\"metadata.creators.person.familyName\",\"metadata.creators.person.givenName\"],\"operator\":\"and\",\"query\":\"" .         $author . "\",\"type\":\"cross_fields\"}}]}},{\"bool\":{\"should\":[{\"nested\":{\"path\":\"files\",\"query\":{\"bool\":{\"must\":[{\"term\":{\"files.storage\":{\"value\":\"INTERNAL_MANAGED\"}}},   {\"bool\":{\"should\":[{\"term\":{\"files.visibility\":{\"value\":\"PRIVATE\"}}},{\"term\":{\"files.visibility\":{\"value\":\"AUDIENCE\"}}},{\"term\":{\"files.visibility\":{\"value\":               \"PUBLIC\"}}}]}}]}},\"score_mode\":\"avg\"}},{\"nested\":{\"path\":\"files\",\"query\":{\"bool\":{\"must\":[{\"term\":{\"files.storage\":{\"value\":\"EXTERNAL_URL\"}}}]}},\"score_mode\":            \"avg\"}}]}}]}}]}}}";


            # some debug for more comfortable testing
            debug "PUREDEL_API request JSON: " . Dumper($queryobject);


            my $ua = LWP::UserAgent->new();
            my $purerequest = HTTP::Request->new('POST', $shost, $header, $queryobject);
            my $pureresponse = $ua->request($purerequest);
            my $responsejson = $pureresponse->content;


            # some debug for more comfortable testing
            my $resstat = $pureresponse->{_rc};
            my $resmsg = $pureresponse->{_msg};
            debug "PUREDEL_API http status: " . $resstat . " - " . $resmsg . "\n";


            my $json = JSON->new;
            my $output = $json->decode($responsejson);

            # some debug for more comfortable testing
            debug "PUREDEL_RESPONSE is: " . Dumper($output);


            foreach my $responserecord (@{$output->{records}}) {
                foreach my $responsefile (@{$responserecord->{data}->{files}}) {

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

        } else {

            $ihost = $ihost . $pureid;
            my $ua = LWP::UserAgent->new();
            my $purerequest = HTTP::Request->new('GET', $ihost);

            my $pureresponse = $ua->request($purerequest);
            my $responsejson = $pureresponse->content;
            my $json = JSON->new;
            my $output = $json->decode($responsejson);

            debug "PURE_RESPONSE is: " . Dumper($output);

            foreach my $responsefile (@{$output->{files}}) {
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

        if (!$preferredmatch) {
            ($preferredmatch) = grep {$_->{'availability'} eq 'PUBLIC' && $_->{'contenttype'} eq 'multimedia'} @filecollection;
            }

        if (!$preferredmatch && $requestaudience) {
            ($preferredmatch) = grep {
                my $filedata = $_;
                grep { $_ eq $requestaudience || $_ eq 'mpg'} @{ $filedata->{'audience'} };
                    } @filecollection
                && grep {$_->{'availability'} eq 'AUDIENCE' && $_->{'contenttype'} eq 'multimedia'
                    } @filecollection;
            }

####################################################################################################################
#assess lookup success / failure                                                                                   #
####################################################################################################################

        if ($preferredmatch) {
            return 0;

            } else {

            my ($preferredmatch) = grep {$_->{'availability'} eq 'PRIVATE' && $_->{'contenttype'} eq 'any-fulltext'} @filecollection;
            debug "PUREDEL triggered by: " . Dumper($preferredmatch);

            if (!$preferredmatch) {
                ($preferredmatch) = grep {$_->{'availability'} eq 'PRIVATE' && $_->{'contenttype'} eq 'pre-print'} @filecollection;
                debug "PUREDEL triggered by: " . Dumper($preferredmatch);
                }

            if (!$preferredmatch) {
                ($preferredmatch) = grep {$_->{'availability'} eq 'PRIVATE' && $_->{'contenttype'} eq 'publisher-version'} @filecollection;
                debug "PUREDEL triggered by: " . Dumper($preferredmatch);
                }

            if (!$preferredmatch) {
                ($preferredmatch) = grep {$_->{'availability'} eq 'PRIVATE' && $_->{'contenttype'} eq 'post-print'} @filecollection;
                debug "PUREDEL triggered by: " . Dumper($preferredmatch);
                }

            unless (!$preferredmatch) {
                return 1;
                } else {
                return 0;
                    }
                }

}

1;