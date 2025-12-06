'use strict';
'require form';
'require fs';
'require rpc';
'require uci';
'require ui';
'require view';

var opacity_sets = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20];
var ts_sets = [0, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 1];

return view.extend({

    load: function() {
        return Promise.all([
            uci.load('kucat')
        ]);
    },

    render: function() {
        var m, s, o;

        m = new form.Map('kucat', _('KuCat Theme Color Schemes'),
            _('Preset color schemes for KuCat UI. You may enable wallpaper blur, adjust transparency, and define RGB values. Only the first enabled scheme is applied.'));

        s = m.section(form.TableSection, 'theme', '');
        s.addremove = true;
        s.anonymous = false;
        s.sortable = true;

        /* Remarks */
        o = s.option(form.Value, 'remarks', _('Remarks'),
            _('Enter a descriptive name for this color scheme.'));
        o.rmempty = false;

        /* Enable scheme */
        o = s.option(form.Flag, 'use', _('Enable scheme'),
            _('Enable this color scheme. Only the first enabled scheme will be used.'));
        o.rmempty = false;
        o.default = '0';

        /* Use wallpaper */
        o = s.option(form.Flag, 'bkuse', _('Use wallpaper'),
            _('Apply desktop wallpaper as background.'));
        o.rmempty = false;
        o.default = '0';

        /* Light / Dark mode */
        o = s.option(form.ListValue, 'mode', _('Theme mode'),
            _('Choose whether this scheme uses light, dark, or automatic mode.'));
        o.value('auto', _('Auto'));
        o.value('light', _('Light'));
        o.value('dark', _('Dark'));
        o.default = 'auto';
        o.rmempty = false;

        /* Main color */
        o = s.option(form.Value, 'primary_rgbm', _('Main Color (RGB)'),
            _("RGB value like '255,0,0' for red, or use preset color names."));
        o.value('blue', _('Royal Blue'));
        o.value('green', _('Medium Sea Green'));
        o.value('orange', _('Sandy Brown'));
        o.value('red', _('Tomato Red'));
        o.value('black', _('Dark Gray (eye comfort)'));
        o.value('gray', _('Cool Night Gray'));
        o.value('bluets', _('Ocean Blue Transparent'));
        o.rmempty = false;
        o.default = '74,161,133';

        /* Wallpaper transparency */
        o = s.option(form.ListValue, 'primary_rgbm_ts', _('Wallpaper transparency'),
            _('Transparency of wallpaper (0: transparent, 1: opaque).'));
        ts_sets.forEach(function(v) {
            o.value(v.toString(), v.toString());
        });
        o.rmempty = false;
        o.default = '0.9';

        /* Wallpaper blur radius */
        o = s.option(form.ListValue, 'primary_opacity', _('Wallpaper blur radius'),
            _('Defines wallpaper blur strength (0 = no blur).'));
        opacity_sets.forEach(function(v) {
            o.value(v.toString(), v.toString());
        });
        o.datatype = 'ufloat';
        o.rmempty = false;
        o.default = '0';

        /* Fence color */
        o = s.option(form.Value, 'primary_rgbs', _('Fence Color (RGB)'),
            _("RGB for section background divider. Suggest using darker tones."));
        o.default = '225,112,88';
        o.rmempty = false;

        /* Fence transparency */
        o = s.option(form.ListValue, 'primary_rgbs_ts', _('Fence transparency'),
            _('Fence background transparency (0: transparent, 1: opaque).'));
        ts_sets.forEach(function(v) {
            o.value(v.toString(), v.toString());
        });
        o.datatype = 'ufloat';
        o.rmempty = false;
        o.default = '0.1';

        return m.render();
    }
});

