# Version: $Id: DDL.pm,v 1.6 2013/03/17 22:26:07 erezsh Exp $
# MPG changes: 2010/12/22 by IOv
# PuRe adaptions: 2026/02/10 by ch
package Parsers::TargetParser::DOCUMENT_DELIVERY::DDL_PURE;
use warnings;
use strict;
use base qw(Parsers::TargetParser);
use URI;

# MPG change: further Perl modules
use Parsers::TargetParser::SUBITO::SUBITO;
use Parsers::TargetParser::PICA::GBVAufsatzDaten;
use LWP::UserAgent;
use HTTP::Request::Common;
use NetWrap::Client qw(get_client_ip);
# MPG change: end

# MPG change: additional parameters added to list
my @params = qw(
        genre
        article
        journal
        abbrev
        bookTitle
        confTitle
        author
        publiPlace
        publisher
        edition
        year
        month
        day
        volume
        issue
        pages
        ISSN
        ISBN
        meduid
        ericID
        oclcnum
        recipient
        source
        note1
        note2
        name
        sender
        id
        pmid
        sid
        place
        patentID
        confTitle
        ip
        delivery_option
        refstr
        doi
        pureid
);
# MPG change: end


sub getDocumentDelivery {

    my ($this)  = @_;
    my $ctx_obj = $this->{ctx_obj};
    my $svc     = $this->{svc};
    # MPG change: cgi required as well
    my $cgi     = $this->{'cgi'};
    # MPG change: end
    my $public_id = "";
    my $special_case  = 1;
    my %query = ();
    my $uri   = "";

    $query{'journal'}    = $ctx_obj->get('rft.jtitle')             if $ctx_obj->get('rft.jtitle');
    $query{'abbrev'}     = @{$ctx_obj->get('rft.stitle')}[0] if $ctx_obj->get('rft.stitle');

    $query{'article'}    = $ctx_obj->get('rft.atitle')             if $ctx_obj->get('rft.atitle');
    $query{'volume'}     = $ctx_obj->get('rft.volume')             if $ctx_obj->get('rft.volume');
    $query{'issue'}      = $ctx_obj->get('rft.issue')              if $ctx_obj->get('rft.issue');
    $query{'year'}       = $ctx_obj->get('rft.year')               if $ctx_obj->get('rft.year');
    $query{'month'}      = $ctx_obj->get('rft.month')              if $ctx_obj->get('rft.month');
    $query{'day'}        = $ctx_obj->get('rft.day')                        if $ctx_obj->get('rft.day');
        ($ctx_obj->get('rft.issn')) ? ( $query{'ISSN'} = $ctx_obj->get('rft.issn') ) : ( $query{'ISSN'} = $ctx_obj->get('rft.eissn') );
        ($ctx_obj->get('rft.isbn')) ? ( $query{'ISBN'} = $ctx_obj->get('rft.isbn') ) : ( $query{'ISBN'} = $ctx_obj->get('rft.eisbn') );
    # MPG change: modify attribute name
    # $query{'meduid'}     = $ctx_obj->get('rft.pmid')             if $ctx_obj->get('rft.pmid');
    $query{'pmid'}     = $ctx_obj->get('rft.pmid')                 if $ctx_obj->get('rft.pmid');
    # MPG change: end
    # MPG change: modify attribute name
    # $query{'source'}     = $ctx_obj->get('sfx.sid')                      if $ctx_obj->get('sfx.sid');;
    # $query{'source'}    .= " (Via SFX)" if $query{'source'};
    $query{'sid'}        = $ctx_obj->get('sfx.sid')                if $ctx_obj->get('sfx.sid');
    $query{'sid'}       .= " (Via SFX)" if $query{'source'};
    $query{'inst'}       = $ctx_obj->get('req.institutes')->[0]    if $ctx_obj->get('req.institutes');
    $query{'doi'}        = $ctx_obj->get('rft.doi')                if $ctx_obj->get('rft.doi');
    # MPG change: end
    $query{'genre'}      = $ctx_obj->get('rft.genre')              if $ctx_obj->get('rft.genre');
    $query{'publisher'}  = $ctx_obj->get('rft.pub')                        if $ctx_obj->get('rft.pub');
    $query{'edition'}    = $ctx_obj->get('rft.edition')            if $ctx_obj->get('rft.edition');
    # MPG change: read more attributes and use stitle as journal if no journal title defined
    $query{'journal'}           = $query{'abbrev'}                        if ($query{'abbrev'} && !($query{'journal'}));
    $query{'patentID'}          = $ctx_obj->get('rft.number')             if $ctx_obj->get('rft.number');
    $query{'confTitle'}         = $ctx_obj->get('rft.confTitle')          if $ctx_obj->get('rft.confTitle');
    $query{'source'}            = $ctx_obj->get('rft.source')             if $ctx_obj->get('rft.source');
#    $query{'doi'}               = $ctx_obj->get('rft.doi')                if $ctx_obj->get('rft.doi');
    $query{'pureid'}            = $ctx_obj->get('PuReId')                 if $ctx_obj->get('PuReId');
    $query{'ip'}                = $ctx_obj->get('req.ip') ? $ctx_obj->get('req.ip') : get_client_ip;;
    $query{'delivery_option'}   = $svc->parse_param('delivery_option');
    $query{'logo'}              = $svc->parse_param('logo');
    # MPG change: end
        if ($query{'genre'} eq "conference") {
                $query{'confTitle'}  = $ctx_obj->get('rft.btitle') if $ctx_obj->get('rft.btitle');
            } else {
                $query{'bookTitle'}  = $ctx_obj->get('rft.btitle') if $ctx_obj->get('rft.btitle');
            }
    my $aulast                   = @{$ctx_obj->get('rft.aulast')}[0] if $ctx_obj->get('rft.aulast');
        my $auinit               = @{$ctx_obj->get('rft.auinit')}[0] if $ctx_obj->get('rft.auinit');
        my $au                           = $ctx_obj->get('rft.au');
    my $spage                    = $ctx_obj->get('rft.spage');
    my $epage                    = $ctx_obj->get('rft.epage');
    $query{'recipient'}  = $svc->parse_param('email');
    $query{'sender'}     = $svc->parse_param('sender');

    # MPG change: use environment for default values
    #   my $host                 = $svc->parse_param('url');
    my $host                 = "http://$ENV{'HTTP_X_FORWARDED_SERVER'}/$ENV{'SFX_INST'}/cgi/public/docdel.cgi";
        $host                    = $svc->parse_param('url') if ($svc->parse_param('url') =~ /^https?:\/\// );
    warn $svc->parse_param('url');
    # MPG change: end

    # generate author
    if($aulast)
        {
        $query{'author'}  =  $aulast;
        $query{'author'} .= ", $auinit" if $auinit;
    }elsif ($au) {
                $query{'author'} = $au;
        }

    # generate page
        if ($spage)
        {
        $query{'pages'}      =  $spage;
        $query{'pages'}     .= "-$epage" if $epage;
        }

    # overrides genre if there is an issn
    if($query{'ISSN'})
        {
        $query{'genre'} = "article";
        # MPG change: add ISSN to journal title
        $query{'journal'} .= " [$query{ISSN}]";
        # MPG change: end
    }

    # MPG extension: add refstring
    $query{'refstr'}    = '';
    $query{'refstr'}    = $query{'article'} . ". " if $query{'article'};
    $query{'refstr'}   .= "In: " . $query{'journal'} ;
    $query{'refstr'}   .= " " . $query{'volume'} if $query{'volume'};
    $query{'refstr'}   .= ", " . $query{'issue'} if $query{'issue'};
    $query{'refstr'}   .= " (" . $query{'year'} . ")" if $query{'year'};
    $query{'refstr'}   .= ": " . $query{'pages'} if $query{'pages'};
    # MPG extension: end

    # MPG extension: add URL to SFX menu
    use MPG::TOOLS::TinyURL;
    my $tiny            = new MPG::TOOLS::TinyURL();
    my $tiny_state      = $tiny->state_int();
    my $tiny_url        = $ctx_obj->get('loc_tinyurl') || '';
    my $openurl         = $ctx_obj->get('sfx.openurl') || '';
    my $resp_type       = $ctx_obj->get('sfx.response_type') || '';

    # check if the tinyURL service is active and a tinyURL should be created
    if ($tiny_state) {
        $tiny_url = $tiny->ctx_to_tinyurl($ctx_obj);
    }

    # replace openURL if a tinyURL is available
    if ($tiny_url) {
        $openurl = $tiny_url;
    }
    $openurl = substr($openurl,0,1000);   # avoid long url
    $query{'sfxmenu_url'} = $openurl;
    # MPG extension: end

    # Decoding the required params in the docdel screen (docdel.cgi)
    my $value;
        foreach my $param (@params)
        {
                $value=$query{$param};
                if($value){
                        use Encode qw(encode_utf8 decode_utf8);
                $value = decode_utf8($value);
                $query{$param}=$value;
                }
        }
    # construct the uri
        $uri = URI->new($host);
        $uri->query_form(%query);

    return ($uri,$special_case);
}

# MPG change: add service
sub getFullTxt {
    my ($this)  = @_;
    return $this->getDocumentDelivery();
}
sub getSelectedFullTxt {
    my ($this)  = @_;
    return $this->getDocumentDelivery();
}
# MPG change: end
1;