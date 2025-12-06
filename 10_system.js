'use strict';
'require baseclass';
'require fs';
'require rpc';

var callLuciVersion = rpc.declare({
	object: 'luci',
	method: 'getVersion'
});

var callSystemBoard = rpc.declare({
	object: 'system',
	method: 'board'
});

var callSystemInfo = rpc.declare({
	object: 'system',
	method: 'info'
});

var callCPUBench = rpc.declare({
	object: 'luci',
	method: 'getCPUBench'
});

var callCPUInfo = rpc.declare({
	object: 'luci',
	method: 'getCPUInfo'
});

var callCPUUsage = rpc.declare({
	object: 'luci',
	method: 'getCPUUsage'
});

var callTempInfo = rpc.declare({
	object: 'luci',
	method: 'getTempInfo'
});

var callOnlineUsers = rpc.declare({
	object: 'luci',
	method: 'getOnlineUsers'
});

return baseclass.extend({
	title: _('System'),

	load: function() {
		return Promise.all([
			L.resolveDefault(callSystemBoard(), {}),
			L.resolveDefault(callSystemInfo(), {}),
			L.resolveDefault(callCPUBench(), {}),
			L.resolveDefault(callCPUInfo(), {}),
			L.resolveDefault(callCPUUsage(), {}),
			L.resolveDefault(callTempInfo(), {}),
			L.resolveDefault(callLuciVersion(), {
				revision: _('unknown version'),
				branch: 'LuCI'
			}),
			L.resolveDefault(callOnlineUsers(), {})
		]);
	},

	render: function(data) {
		var boardinfo   = data[0];
		var systeminfo  = data[1];
		var cpubench    = data[2];
		var cpuinfo     = data[3];
		var cpuusage    = data[4];
		var tempinfo    = data[5];
		var luciversion = data[6];
		var onlineusers = data[7];

		var luciVersionStr = luciversion.branch + ' ' + luciversion.revision;

		var datestr = null;
		if (systeminfo.localtime) {
			var date = new Date(systeminfo.localtime * 1000);
			datestr = '%04d-%02d-%02d %02d:%02d:%02d'.format(
				date.getUTCFullYear(),
				date.getUTCMonth() + 1,
				date.getUTCDate(),
				date.getUTCHours(),
				date.getUTCMinutes(),
				date.getUTCSeconds()
			);
		}

		var fields = [
			_('Hostname'), boardinfo.hostname,
			_('Compiler'), 'SopekSemprit',
			_('Model'), boardinfo.model + (cpubench.cpubench || ''),
			_('Firmware Version'), 'NSS Revamp v2.0 (Immortalwrt 24.10)',
			_('Kernel Version'), boardinfo.kernel,
			_('Local Time'), datestr,
			_('Uptime'), systeminfo.uptime ? '%t'.format(systeminfo.uptime) : null,
			_('Online Users'), onlineusers ? onlineusers.onlineusers : '?'
		];

		if (tempinfo.tempinfo) {
			fields.splice(6, 0, _('Temperature'));
			fields.splice(7, 0, tempinfo.tempinfo);
		}

		var table = E('table', { 'class': 'table' });

		for (var i = 0; i < fields.length; i += 2) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [ fields[i] ]),
				E('td', { 'class': 'td left' }, [
					fields[i + 1] != null ? fields[i + 1] : '?'
				])
			]));
		}

		return table;
	}
});

