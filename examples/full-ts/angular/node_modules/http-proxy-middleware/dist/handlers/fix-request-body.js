"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.fixRequestBody = void 0;
const querystring = require("querystring");
/**
 * Fix proxied body if bodyParser is involved.
 */
function fixRequestBody(proxyReq, req, res) {
    const requestBody = req.body;
    if (!requestBody) {
        return;
    }
    const contentType = proxyReq.getHeader('Content-Type');
    if (!contentType) {
        return;
    }
    // Handle bad request when unexpected "Connect: Upgrade" header is provided
    if (/upgrade/gi.test(proxyReq.getHeader('Connection'))) {
        handleBadRequest({ proxyReq, req, res });
        return;
    }
    // Handle bad request when invalid request body is provided
    if (hasInvalidKeys(requestBody)) {
        handleBadRequest({ proxyReq, req, res });
        return;
    }
    const writeBody = (bodyData) => {
        // deepcode ignore ContentLengthInCode: bodyParser fix
        proxyReq.setHeader('Content-Length', Buffer.byteLength(bodyData));
        proxyReq.write(bodyData);
    };
    if (contentType.includes('application/json')) {
        writeBody(JSON.stringify(requestBody));
    }
    else if (contentType.includes('application/x-www-form-urlencoded')) {
        writeBody(querystring.stringify(requestBody));
    }
}
exports.fixRequestBody = fixRequestBody;
function hasInvalidKeys(obj) {
    return Object.keys(obj).some((key) => /[\n\r]/.test(key));
}
function handleBadRequest({ proxyReq, req, res }) {
    res.writeHead(400);
    res.end('Bad Request');
    proxyReq.destroy();
    req.destroy();
}
