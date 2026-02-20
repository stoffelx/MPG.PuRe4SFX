# MPG PuRe docdel PlugIn: offer contact form to deliver private full texts
#
# version 0.1 - 2025-02-20, ch
package Parsers::PlugIn::MPG_PURE_DOCDEL;

use base qw(Parsers::PlugIn);
use Parsers::PlugIn::SUPER_PLUGIN;
use SFXMenu::Debug qw(debug error);

sub lookup {
        my ($this,$ctx_obj)     = @_;

        if (! $ctx_obj->get('loc_pure_return')) {
                debug "Execute SUPER_PLUGIN";
                Parsers::PlugIn::SUPER_PLUGIN::lookup($this,$ctx_obj);
        }

        my $ret = $ctx_obj->get('loc_pure_return');
        debug "loc_pure_return is: $ret";
        $ret eq 'P' ? return 1 : return 0;
}

1;