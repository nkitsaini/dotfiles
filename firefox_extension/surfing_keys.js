// an example to create a new mapping `ctrl-y`
api.mapkey('<ctrl-y>', 'Show me the money', function() {
    Front.showPopup('a well-known phrase uttered by characters in the 1996 film Jerry Maguire (Escape to close).');
});

// an example to replace `T` with `gt`, click `Default mappings` to see how `T` works.
api.map('gt', 'T');
api.map('J', 'E');
api.map('K', 'R');

for (const key of 'jkbts?') {
    api.unmap(key, /hn.nkit.dev/);
}

api.mapkey('yY', '#1Copy all tabs url', function() {
	runtime.command({action: 'getTabs'}, function (response) {
	 Clipboard.write(response.tabs.map(tab => tab.url).join('\n'));
	});
});
api.map('<Ctrl-i>', '<Alt-s>'); // hotkey must be one keystroke with/without modifier, it can not be a sequence of keystrokes like `gg`.

api.unmap('i', /youtube.com/);
api.unmap('f', /youtube.com/);

api.unmapAllExcept([], /github.dev/);
api.unmapAllExcept([], /linear.app/);
api.unmapAllExcept([], /localhost/);
api.unmapAllExcept([], /us-east-1.console.aws.amazon.com\/systems-manager\/session-manager/);
api.unmapAllExcept([], /\/\/whimsical.com/);

// an example to remove mapkey `Ctrl-i`
api.unmap('<ctrl-i>');

// set theme
settings.theme = `
.sk_theme {
    font-family: Input Sans Condensed, Charcoal, sans-serif;
    font-size: 10pt;
    background: #24272e;
    color: #abb2bf;
}
.sk_theme tbody {
    color: #fff;
}
.sk_theme input {
    color: #d0d0d0;
}
.sk_theme .url {
    color: #61afef;
}
.sk_theme .annotation {
    color: #56b6c2;
}
.sk_theme .omnibar_highlight {
    color: #528bff;
}
.sk_theme .omnibar_timestamp {
    color: #e5c07b;
}
.sk_theme .omnibar_visitcount {
    color: #98c379;
}
.sk_theme #sk_omnibarSearchResult ul li:nth-child(odd) {
    background: #303030;
}
.sk_theme #sk_omnibarSearchResult ul li.focused {
    background: #3e4452;
}
#sk_status, #sk_find {
    font-size: 20pt;
}`;
// click `Save` button to make above settings to take effect.</ctrl-i></ctrl-y>
