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

            // Auto-render LaTeX math formulas if KaTeX is available
            if (window.renderMathInElement) {
              try {
                window.renderMathInElement(contentDiv, {
                  delimiters: [
                    { left: "$$", right: "$$", display: true },
                    { left: "\\[", right: "\\]", display: true },
                    { left: "$", right: "$", display: false },
                    { left: "\\(", right: "\\)", display: false }
                  ],
                  throwOnError: false
                });
              } catch (mathErr) {
                console.warn("KaTeX math auto-render error:", mathErr);
              }
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

  window.renderPdfToElement = function(targetOrId, base64Data) {
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
        try {
          var cleanB64 = base64Data;
          if (cleanB64.indexOf("base64,") !== -1) {
            cleanB64 = cleanB64.split("base64,")[1];
          }
          cleanB64 = cleanB64.replace(/\s+/g, "");
          var binaryString = window.atob(cleanB64);
          var len = binaryString.length;
          var bytes = new Uint8Array(len);
          for (var i = 0; i < len; i++) {
            bytes[i] = binaryString.charCodeAt(i);
          }
          var blob = new Blob([bytes], { type: "application/pdf" });
          var blobUrl = URL.createObjectURL(blob);

          container.innerHTML = "";
          var iframe = document.createElement("iframe");
          // Standard PDF open parameters to suppress browser's duplicate toolbar and sidebar
          iframe.src = blobUrl + "#toolbar=0&navpanes=0&scrollbar=1";
          iframe.style.width = "100%";
          iframe.style.height = "100%";
          iframe.style.border = "none";
          container.appendChild(iframe);
          resolve({ success: true, url: blobUrl });
        } catch (e) {
          console.error("PDF rendering error:", e);
          reject(e.toString());
        }
      }
      attempt(6);
    });
  };

  window.setPdfViewerPage = function(targetOrId, pageNum) {
    var container = _findDocxContainer(targetOrId);
    if (container) {
      var iframe = container.querySelector("iframe");
      if (iframe && iframe.src) {
        var base = iframe.src.split("#")[0];
        iframe.src = base + "#page=" + pageNum + "&toolbar=0&navpanes=0&scrollbar=1";
      }
    }
  };

  window.printPdfViewer = function(targetOrId) {
    var container = targetOrId ? _findDocxContainer(targetOrId) : null;
    if (container) {
      var iframe = container.querySelector("iframe");
      if (iframe && iframe.contentWindow) {
        try {
          iframe.contentWindow.focus();
          iframe.contentWindow.print();
          return true;
        } catch(e) {}
      }
    }
    window.print();
    return true;
  };
})();
