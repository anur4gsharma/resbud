// Resbud DOCX Helper - in-browser DOCX rendering using docx-preview
(function() {
  window.docxViewerInstances = window.docxViewerInstances || {};

  function _findDocxContainer(targetOrId) {
    if (!targetOrId) return null;
    if (typeof targetOrId !== 'string' && targetOrId.nodeType) {
      return targetOrId;
    }
    var id = String(targetOrId);
    var el = document.getElementById(id);
    if (el) return el;
    var flutterViews = document.querySelectorAll('flutter-view, flt-glass-pane');
    for (var i = 0; i < flutterViews.length; i++) {
      var sr = flutterViews[i].shadowRoot;
      if (sr) {
        var found = sr.getElementById(id) || sr.querySelector('#' + id);
        if (found) return found;
      }
    }
    var all = document.querySelectorAll('*');
    for (var j = 0; j < all.length; j++) {
      if (all[j].shadowRoot) {
        var f = all[j].shadowRoot.getElementById(id) || all[j].shadowRoot.querySelector('#' + id);
        if (f) return f;
      }
    }
    return null;
  }

  window.renderDocxToElement = function(targetOrId, base64Data, zoomLevel) {
    return new Promise(function(resolve, reject) {
      function attempt(retriesLeft) {
        var container = _findDocxContainer(targetOrId);
        if (!container) {
          if (retriesLeft > 0) {
            setTimeout(function() { attempt(retriesLeft - 1); }, 70);
            return;
          }
          return reject("Container element not found: " + targetOrId);
        }
        if (!window.docx) {
          return reject("docx-preview library is not available");
        }

        try {
          var binaryString = window.atob(base64Data);
          var bytes = new Uint8Array(binaryString.length);
          for (var i = 0; i < binaryString.length; i++) {
            bytes[i] = binaryString.charCodeAt(i);
          }

          container.innerHTML = "";
          var contentDiv = document.createElement("div");
          contentDiv.className = "docx-rendered-pages";
          contentDiv.style.display = "flex";
          contentDiv.style.flexDirection = "column";
          contentDiv.style.alignItems = "center";
          contentDiv.style.padding = "24px 0";
          contentDiv.style.minHeight = "100%";
          contentDiv.style.width = "100%";
          contentDiv.style.boxSizing = "border-box";
          contentDiv.style.backgroundColor = "#525659";
          contentDiv.style.overflowY = "auto";
          contentDiv.style.overflowX = "auto";
          container.appendChild(contentDiv);

          window.docx.renderAsync(bytes.buffer, contentDiv, null, {
            inWrapper: true,
            ignoreWidth: false,
            ignoreHeight: false,
            experimental: true,
            breakPages: true,
            trimXmlDeclaration: true,
            renderHeaders: true,
            renderFooters: true,
            renderFootnotes: true,
            renderEndnotes: true
          }).then(function() {
            var pages = contentDiv.querySelectorAll(".docx");
            var pageCount = pages.length > 0 ? pages.length : 1;

            for (var p = 0; p < pages.length; p++) {
              pages[p].style.boxShadow = "0 6px 18px rgba(0, 0, 0, 0.35)";
              pages[p].style.marginBottom = "24px";
              pages[p].style.backgroundColor = "#ffffff";
              pages[p].style.borderRadius = "2px";
            }

            var currentZoom = zoomLevel || 1.0;
            if (currentZoom !== 1.0) {
              contentDiv.style.transform = "scale(" + currentZoom + ")";
              contentDiv.style.transformOrigin = "top center";
            }

            if (container.id) {
              window.docxViewerInstances[container.id] = {
                contentDiv: contentDiv,
                pageCount: pageCount,
                zoom: currentZoom
              };
            }

            resolve({
              success: true,
              pageCount: pageCount
            });
          }).catch(function(err) {
            console.error("DOCX rendering error:", err);
            reject(err.toString());
          });
        } catch (e) {
          console.error("DOCX parsing error:", e);
          reject(e.toString());
        }
      }
      attempt(6);
    });
  };

  window.setDocxZoom = function(targetOrId, zoomLevel) {
    var container = _findDocxContainer(targetOrId);
    if (!container) return false;
    var contentDiv = container.querySelector(".docx-rendered-pages");
    if (contentDiv) {
      contentDiv.style.transform = "scale(" + (zoomLevel || 1.0) + ")";
      contentDiv.style.transformOrigin = "top center";
      return true;
    }
    return false;
  };
})();
