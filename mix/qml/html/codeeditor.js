var editor = CodeMirror(document.body, {
							lineNumbers: true,
							//styleActiveLine: true,
							matchBrackets: true,
							autofocus: true,
							gutters: ["CodeMirror-linenumbers", "breakpoints"],
							autoCloseBrackets: true
						});
var ternServer;

editor.setOption("theme", "solarized dark");
editor.setOption("indentUnit", 4);
editor.setOption("indentWithTabs", true);
editor.setOption("fullScreen", true);

editor.changeRegistered = false;
editor.breakpointsChangeRegistered = false;

editor.on("change", function(eMirror, object) {
	editor.changeRegistered = true;
});

var mac = /Mac/.test(navigator.platform);
if (mac === true) {
editor.setOption("extraKeys", {
	"Cmd-V": function(cm) {
		cm.replaceSelection(clipboard);
	},
	"Cmd-X": function(cm) {
		window.document.execCommand("cut");
	},
	"Cmd-C": function(cm) {
		window.document.execCommand("copy");
	}});
}

makeMarker = function() {
  var marker = document.createElement("div");
  marker.style.color = "#822";
  marker.innerHTML = "●";
  return marker;
};

toggleBreakpointLine = function(n) {
	var info = editor.lineInfo(n);
	editor.setGutterMarker(n, "breakpoints", info.gutterMarkers ? null : makeMarker());
	editor.breakpointsChangeRegistered = true;
}

editor.on("gutterClick", function(cm, n) {
	toggleBreakpointLine(n);
});

toggleBreakpoint = function() {
	var line = editor.getCursor().line;
	toggleBreakpointLine(line);
}

getTextChanged = function() {
	return editor.changeRegistered;
};

getText = function() {
	editor.changeRegistered = false;
	return editor.getValue();
};

getBreakpointsChanged = function() {
	return editor.changeRegistered || editor.breakpointsChangeRegistered;   //TODO: track new lines
};

getBreakpoints = function() {
	var locations = [];
	editor.breakpointsChangeRegistered = false;
	var doc = editor.doc;
	doc.iter(function(line) {
		if (line.gutterMarkers && line.gutterMarkers["breakpoints"]) {
			var l = doc.getLineNumber(line);
			locations.push({
				start: editor.indexFromPos({ line: l, ch: 0}),
				end: editor.indexFromPos({ line: l + 1, ch: 0})
			});;
		}
	});
	return locations;
};

setTextBase64 = function(text) {
	editor.setValue(window.atob(text));
	editor.getDoc().clearHistory();
	editor.focus();
};

setText = function(text) {
	editor.setValue(text);
};

setMode = function(mode) {
	this.editor.setOption("mode", mode);

	if (mode === "javascript")
	{
		ternServer = new CodeMirror.TernServer({defs: [ ecma5Spec() ]});
		editor.setOption("extraKeys", {
							 "Ctrl-Space": function(cm) { ternServer.complete(cm); },
							 "Ctrl-I": function(cm) { ternServer.showType(cm); },
							 "Ctrl-O": function(cm) { ternServer.showDocs(cm); },
							 "Alt-.": function(cm) { ternServer.jumpToDef(cm); },
							 "Alt-,": function(cm) { ternServer.jumpBack(cm); },
							 "Ctrl-Q": function(cm) { ternServer.rename(cm); },
							 "Ctrl-.": function(cm) { ternServer.selectName(cm); },
							 "'.'": function(cm) { setTimeout(function() { ternServer.complete(cm); }, 100); throw CodeMirror.Pass; }
						 })
		editor.on("cursorActivity", function(cm) { ternServer.updateArgHints(cm); });
	}
	else if (mode === "solidity")
	{
		CodeMirror.commands.autocomplete = function(cm) {
				CodeMirror.showHint(cm, CodeMirror.hint.anyword);
		}
		editor.setOption("extraKeys", {
							 "Ctrl-Space": "autocomplete"
						 })
	}
};

setClipboardBase64 = function(text) {
	clipboard = window.atob(text);
};

var executionMark;
highlightExecution = function(start, end) {
	if (executionMark)
		executionMark.clear();
	executionMark = editor.markText(editor.posFromIndex(start), editor.posFromIndex(end), { className: "CodeMirror-exechighlight" });
}

var changeId;
changeGeneration = function()
{
	changeId = editor.changeGeneration(true);
}

isClean = function()
{
	return editor.isClean(changeId);
}
