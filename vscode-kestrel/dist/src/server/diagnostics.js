"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.compilerDiagnosticToLsp = compilerDiagnosticToLsp;
exports.toLspDiagnostics = toLspDiagnostics;
const path = __importStar(require("node:path"));
const node_url_1 = require("node:url");
const node_1 = require("vscode-languageserver/node");
function toRange(loc) {
    const startLine = Math.max(loc.line - 1, 0);
    const startChar = Math.max(loc.column - 1, 0);
    const endLine = Math.max((loc.endLine ?? loc.line) - 1, 0);
    const endChar = Math.max((loc.endColumn ?? (loc.column + 1)) - 1, 0);
    return {
        start: { line: startLine, character: startChar },
        end: { line: endLine, character: Math.max(endChar, startChar + 1) },
    };
}
function toFileUri(file, defaultUri) {
    if (path.isAbsolute(file)) {
        return (0, node_url_1.pathToFileURL)(file).toString();
    }
    return defaultUri;
}
function buildRelatedInformation(diag, defaultUri) {
    const related = [];
    for (const rel of diag.related ?? []) {
        const location = {
            uri: toFileUri(rel.location.file, defaultUri),
            range: toRange(rel.location),
        };
        related.push({ location, message: rel.message });
    }
    const baseLocation = {
        uri: defaultUri,
        range: toRange(diag.location),
    };
    if (diag.hint != null && diag.hint.length > 0) {
        related.push({ location: baseLocation, message: `hint: ${diag.hint}` });
    }
    if (diag.suggestion != null && diag.suggestion.length > 0) {
        related.push({ location: baseLocation, message: `suggestion: ${diag.suggestion}` });
    }
    return related.length > 0 ? related : undefined;
}
function compilerDiagnosticToLsp(diag, uri) {
    return {
        severity: diag.severity === 'warning' ? node_1.DiagnosticSeverity.Warning : node_1.DiagnosticSeverity.Error,
        code: diag.code,
        source: 'kestrel',
        message: diag.message,
        range: toRange(diag.location),
        relatedInformation: buildRelatedInformation(diag, uri),
    };
}
function toLspDiagnostics(uri, diagnostics) {
    return diagnostics.map((diag) => compilerDiagnosticToLsp(diag, uri));
}
//# sourceMappingURL=diagnostics.js.map