'use strict';
'require form';
'require fs';
'require rpc';
'require uci';
'require ui';
'require view';

var callAvailSpace = rpc.declare({
    object: 'luci.kucatconfig',
    method: 'space'
});

var callDelkucat = rpc.declare({
    object: 'luci.kucatconfig',
    method: 'deld',
    params: ['filename'],
    expect: { '': {} }
});

var callRenamekucat = rpc.declare({
    object: 'luci.kucatconfig',
    method: 'renamed',
    params: ['newname'],
    expect: { '': {} }
});

var callReadFile = rpc.declare({
    object: 'luci.kucatconfig',
    method: 'read_file',
    params: ['filename'],
    expect: { '': {} }
});

var bg_path = '/www/luci-static/kucat/background/';

return view.extend({

    load: function() {
        return Promise.all([
            uci.load('kucat'),
            L.resolveDefault(callAvailSpace(), {}),
            L.resolveDefault(fs.list(bg_path), {})
        ]);
    },

    render: function(data) {
        var m, s, o;

        var spaceInfo = data[1] || {};
        var blocks = spaceInfo.space || 0;

        var container = E('div', { 'class': 'cbi-map' });

        /* ------- STYLES ------- */
        container.appendChild(E('style', {}, `
            .view-mode-toggle { margin: 0 15px; display: flex; }
            .view-mode-btn { padding: 8px 16px; background: #999; cursor: pointer; border-radius: 4px; }
            .view-mode-btn.active { background: #007cff; color: white; }

            .grid-view {
                display: grid;
                grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
                gap: 15px; margin: 0 15px;
            }
            .grid-item {
                border: 1px solid #ddd; border-radius: 8px;
                padding: 10px; background: white; cursor: pointer;
                transition: all .3s ease; position: relative;
            }
            .grid-item.selected { border-color: #007cff; background: #e8f1ff; }
            .grid-preview { width:100%; height:120px; object-fit:cover; border-radius:4px; }

            .image-error, .grid-image-error {
                background:#f0f0f0; display:flex; justify-content:center;
                align-items:center; color:#999; font-size:12px;
            }
            .image-error { width:80px; height:60px; border:1px solid #ddd; }
            .grid-image-error { width:100%; height:120px; border-radius:4px; }

            .preview-modal {
                position:fixed; top:0; left:0; width:100%; height:100%;
                background:rgba(0,0,0,.8); display:flex; align-items:center;
                justify-content:center; z-index:9999;
            }
        `));

        container.appendChild(E('h3', _('Desktop Wallpaper Upload')));

        container.appendChild(E('div', { 'class': 'cbi-section-descr' }, [
            E('p', _('Available space: %1024.2mB').format(blocks * 1024)),
            E('p', _('You can upload gif/jpg/png/webp files as desktop wallpapers.')),
            E('p', _('Files are saved to: ') + bg_path)
        ]));

        /* Upload button */
        container.appendChild(E('button', {
            'class': 'btn cbi-button cbi-button-action',
            'style': 'margin:10px 0;',
            'click': ui.createHandlerFn(this, function(ev) {
                var tmpfile = '/tmp/kucat_desktop_bg.tmp';

                return ui.uploadFile(tmpfile, ev.target).then(function(res) {
                    if (!res || !res.name)
                        throw new Error(_('No file selected or upload failed'));

                    return L.resolveDefault(callRenamekucat(res.name), {}).then(function(ret) {
                        if (ret && ret.result === 0) {
                            ui.addNotification(null, E('p', _('File uploaded successfully!')));
                            setTimeout(() => location.reload(), 800);
                        } else {
                            ui.addNotification(null, E('p',
                                _('Failed to upload file: %s').format(ret.error || 'Unknown error')));
                            fs.remove(tmpfile);
                        }
                    });
                }).catch(function(e) {
                    ui.addNotification(null, E('p', _('Upload error: %s').format(e.message)));
                    fs.remove(tmpfile);
                });
            })
        }, _('Upload…')));

        /* File list */
        var files = data[2] || [];

        container.appendChild(E('h3', _('Background file list')));

        if (files.length === 0) {
            container.appendChild(E('p', E('em', _('No files found.'))));
            return container;
        }

        /* --- LIST + GRID VIEW SWITCHER --- */
        var selectedFiles = new Set();
        var allFileNames = files.map(f => f.name);

        var listView = E('table', { 'class': 'table cbi-section-table', 'style': 'display:table;' }, [
            E('tr', { 'class': 'tr table-titles' }, [
                E('th', _('Select')),
                E('th', _('Preview')),
                E('th', _('Filename')),
                E('th', _('Modified')),
                E('th', _('Size'))
            ])
        ]);

        var gridView = E('div', { 'class': 'grid-view', 'style': 'display:none;' });

        /* --- view toggle --- */
        container.appendChild(E('div', { 'class': 'view-mode-toggle' }, [
            E('button', {
                'class': 'view-mode-btn active',
                'click': ui.createHandlerFn(this, function(ev) {
                    listView.style.display = 'table';
                    gridView.style.display = 'none';
                    document.querySelectorAll('.view-mode-btn').forEach(b => b.classList.remove('active'));
                    ev.target.classList.add('active');
                    selectedFiles.clear();
                })
            }, _('List View')),
            E('button', {
                'class': 'view-mode-btn',
                'click': ui.createHandlerFn(this, function(ev) {
                    listView.style.display = 'none';
                    gridView.style.display = 'grid';
                    document.querySelectorAll('.view-mode-btn').forEach(b => b.classList.remove('active'));
                    ev.target.classList.add('active');
                    selectedFiles.clear();
                })
            }, _('Grid View'))
        ]));

        /* --- selection actions --- */
        var selectionInfo = E('div', { 'style': 'margin:8px 15px; font-weight:bold;' }, _('Selected: 0 files'));

        function updateSelection() {
            selectionInfo.textContent =
                _('Selected: %d of %d files').format(selectedFiles.size, allFileNames.length);
        }

        container.appendChild(selectionInfo);

        /* --- Populate list and grid --- */
        files.forEach(file => {
            var previewUrl = '/luci-static/kucat/background/' + file.name + '?t=' + Date.now();

            /* LIST VIEW ROW */
            var row = E('tr', { 'class': 'tr' });

            var cb = E('input', {
                'type': 'checkbox',
                'value': file.name,
                'class': 'file-checkbox',
                'change': function(ev) {
                    ev.target.checked ? selectedFiles.add(file.name) : selectedFiles.delete(file.name);
                    updateSelection();
                }
            });

            row.appendChild(E('td', [cb]));

            row.appendChild(E('td', [
                E('img', {
                    'src': previewUrl,
                    'style': 'width:80px;height:60px;cursor:pointer;object-fit:cover;',
                    'onerror': "this.style.display='none'; this.nextElementSibling.style.display='block';",
                    'click': () => showPreview(file, previewUrl)
                }),
                E('div', { 'class': 'image-error', 'style': 'display:none;' }, _('Unknown file'))
            ]));

            row.appendChild(E('td', file.name));
            row.appendChild(E('td', new Date(file.mtime * 1000).toLocaleString()));
            row.appendChild(E('td', String.format('%1024.2mB', file.size)));

            listView.appendChild(row);

            /* GRID VIEW ITEM */
            var gridItem = E('div', { 'class': 'grid-item' });

            var gridCB = E('input', {
                'type': 'checkbox',
                'value': file.name,
                'class': 'grid-checkbox',
                'change': function(ev) {
                    ev.stopPropagation();
                    ev.target.checked ? selectedFiles.add(file.name) : selectedFiles.delete(file.name);
                    gridItem.classList.toggle('selected', ev.target.checked);
                    updateSelection();
                }
            });

            gridItem.appendChild(gridCB);

            gridItem.appendChild(E('img', {
                'class': 'grid-preview',
                'src': previewUrl,
                'onerror': "this.style.display='none'; this.nextElementSibling.style.display='flex';"
            }));

            gridItem.appendChild(E('div', { 'class': 'grid-image-error', 'style': 'display:none;' },
                _('Unknown file')
            ));

            gridItem.appendChild(E('div', { 'class': 'grid-name' }, file.name));
            gridItem.appendChild(E('div', { 'class': 'grid-info' }, [
                String.format('%1024.2mB', file.size),
                E('br'),
                new Date(file.mtime * 1000).toLocaleDateString()
            ]));

            gridItem.addEventListener('click', function(ev) {
                if (!ev.target.matches('input')) showPreview(file, previewUrl);
            });

            gridView.appendChild(gridItem);
        });

        container.appendChild(listView);
        container.appendChild(gridView);

        /* --- preview modal --- */
        function showPreview(file, url) {
            var modal = E('div', { 'class': 'preview-modal' }, [
                E('div', {
                    'style': 'background:white;padding:20px;border-radius:6px;max-width:90%;max-height:90%;'
                }, [
                    E('img', {
                        'src': url,
                        'style': 'max-width:100%;max-height:80vh;border-radius:4px;'
                    }),
                    E('div', { 'style':'margin-top:10px;color:#333;text-align:center;' }, [
                        file.name,
                        E('br'),
                        _('Size: %1024.2mB, Modified: %s')
                            .format(file.size, new Date(file.mtime * 1000).toLocaleString())
                    ])
                ])
            ]);

            modal.addEventListener('click', e => { if (e.target === modal) modal.remove() });

            document.body.appendChild(modal);
        }

        return container;
    },

    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});

