// Resbud DOCX Helper - in-browser DOCX rendering using docx-preview
(function() {
  window.docxViewerInstances = window.docxViewerInstances || {};

  window.renderDocxToElement = function(containerId, base64Data, zoomLevel) {
    return new Promise(function(resolve, reject) {
      var container = document.getElementById(containerId);
      if (!container) {
        return reject("Container element not found: " + containerId);
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
          renderFooters: true
        }).then(function() {
          var pages = contentDiv.querySelectorAll(".docx");
          var pageCount = pages.length > 0 ? pages.length : 1;

          // Apply page shadows and styling
          for (var p = 0; p < pages.length; p++) {
            pages[p].style.boxShadow = "0 6px 18px rgba(0, 0, 0, 0.3)";
            pages[p].style.marginBottom = "24px";
            pages[p].style.backgroundColor = "#ffffff";
            pages[p].style.borderRadius = "2px";
          }

          var currentZoom = zoomLevel || 1.0;
          if (currentZoom !== 1.0) {
            contentDiv.style.transform = "scale(" + currentZoom + ")";
            contentDiv.style.transformOrigin = "top center";
          }

          window.docxViewerInstances[containerId] = {
            contentDiv: contentDiv,
            pageCount: pageCount,
            zoom: currentZoom
          };

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
    });
  };

  window.setDocxZoom = function(containerId, zoomLevel) {
    var instance = window.docxViewerInstances[containerId];
    if (instance && instance.contentDiv) {
      instance.zoom = zoomLevel;
      instance.contentDiv.style.transform = "scale(" + zoomLevel + ")";
      instance.contentDiv.style.transformOrigin = "top center";
      return true;
    }
    return false;
  };
})();
