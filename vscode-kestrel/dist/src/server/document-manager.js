"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DocumentManager = void 0;
class DocumentManager {
    docs = new Map();
    update(uri, source, ast, diagnostics) {
        this.docs.set(uri, { source, ast, diagnostics });
    }
    get(uri) {
        return this.docs.get(uri);
    }
    delete(uri) {
        this.docs.delete(uri);
    }
}
exports.DocumentManager = DocumentManager;
//# sourceMappingURL=document-manager.js.map