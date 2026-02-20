        my %lookup = (
                pure => 'mpg_pure.config',
        );

######################### MPG PuRe
sub create_request_pure {
        my $ctx_obj = $_[0];
        my $conf = $_[1];

        # read attributes from context object
        my $title  =     $ctx_obj->get('rft.atitle') || $ctx_obj->get('rft.btitle');
        my $author =     ($ctx_obj->get('@rft.aulast') && $ctx_obj->get('@rft.aulast')->[0]) ? $ctx_obj->get('@rft.aulast')->[0] : '';
        my $inst   =     $ctx_obj->{'@req.institutes'}->[0] || '';
        my $pureid =     $ctx_obj->get('pureid') || '';

        # read params from config file
        my $config_parser       = new Manager::Config(file=>$conf);
        my $ihost               = $config_parser->getSection('host','item');
        my $shost               = $config_parser->getSection('host','search');

        my $requestaudience = '';
        if ($inst) {
            $requestaudience = $config_parser->getSection('audience', $inst);
            $ctx_obj->set('loc_pure_inst', $requestaudience);
            } else {
            debug "institute context not eligible for PuRe request (probably missing)";
            $ctx_obj->set('loc_pure_return','N');
            return 0;
        }

        # some debug for more comfortable testing
        debug "PURE_INSTITUTE is: $inst";
        debug "PURE_REQUEST_AUDIENCE is: $requestaudience";
        debug "PURE_ID is: $pureid";

        # initiate API request
        if (!$pureid) {

            # author formatting for API request
            $author =~ s/,.*//g;

            my $header = [
                'Content-Type' => 'application/json'
                ];

            my $queryobject = "{\"query\":{\"bool\":{\"must\":[{\"term\":{\"publicState\":{\"value\":\"RELEASED\"}}},{\"term\":{\"versionState\":{\"value\":\"RELEASED\"}}},{\"bool\":{\"must\":      [{\"bool\":{\"must\":[{\"bool\":{\"should\":[{\"match\":{\"metadata.title\":{\"operator\":\"and\",\"query\":\"" . $title . "\"}}},{\"match\":{\"metadata.alternativeTitles.value\":{\"operator\":     \"and\",\"query\":\"" . $title . "\"}}}]}},{\"multi_match\":{\"fields\":[\"metadata.creators.person.familyName\",\"metadata.creators.person.givenName\"],\"operator\":\"and\",\"query\":\"" .         $author . "\",\"type\":\"cross_fields\"}}]}},{\"bool\":{\"should\":[{\"nested\":{\"path\":\"files\",\"query\":{\"bool\":{\"must\":[{\"term\":{\"files.storage\":{\"value\":\"INTERNAL_MANAGED\"}}}]}},\"score_mode\":\"avg\"}},{\"nested\":{\"path\":\"files\",\"query\":{\"bool\":{\"must\":[{\"term\":{\"files.storage\":{\"value\":\"EXTERNAL_URL\"}}}]}},\"score_mode\":\"avg\"}}]}}]}}]}}}";

            # some debug for more comfortable testing
            debug "PURE_API request JSON: " . Dumper($queryobject);

            $uri = URI->new($shost);
            return HTTP::Request->new(POST => $uri, $header, $queryobject);

        } else {

            my $url = $ihost . $pureid;
            $uri = URI->new($url);
            return HTTP::Request->new(GET => $uri);

        }
}


sub parse_response_pure {
    my $ctx_obj = $_[0];
    my $response = $_[1];
    my $ret = 'N';


    if ($response->is_success) {

        my $requestaudience = $ctx_obj->get('loc_pure_inst');

        # data structure declaration
        my @filecollection = ();
        my %filedata;
        my @audiences = ();

        # some debug for more comfortable testing
        my $resstat = $response->{_rc};
        my $resmsg = $response->{_msg};
        debug "PURE_API http status: " . $resstat . " - " . $resmsg;

        my $json = JSON->new;
        my $output = $json->decode($response->content);

        # some debug for more comfortable testing
        debug "PURE_RESPONSE is: " . Dumper($output);

        # parsing depends on response type (PuReId vs. author/title search)
        if ($output->{'numberOfRecords'}) {
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

        #iterate @filecollection for preferred delivery file
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


        #return positive flag if full text is accessible
        if ($preferredmatch) {
            $ret = 'Y';
            debug "loc_pure_return is: " . $ret;

            $ctx_obj->set('loc_pure_return', $ret);
            return $ret


        #check for private files to trigger delivery request form
        } elsif (!$preferredmatch) {

            ($preferredmatch) = grep {$_->{'availability'} eq 'PRIVATE' && $_->{'contenttype'} eq 'any-fulltext'} @filecollection;
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

            if ($preferredmatch) {
                $ret = 'P';
                debug "loc_pure_return is: " . $ret;

                $ctx_obj->set('loc_pure_return', $ret);
                return $ret
                }
            }


        } else {

            debug $response->status_line;
    }
}