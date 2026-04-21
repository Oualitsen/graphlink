import { createReadStream, statSync } from 'fs';
import { resolve } from 'path';
import FormData from 'form-data';
import fetch from 'node-fetch';

const SERVER = 'http://localhost:4000/graphql';
const FILE = resolve('./tsconfig.json');

const query = `
  mutation UploadFile($file: Upload!) {
    uploadFile(file: $file) {
      filename
      size
      mimetype
    }
  }
`;

const form = new FormData();
form.append('operations', JSON.stringify({ query, variables: { file: null } }));
form.append('map', JSON.stringify({ '0': ['variables.file'] }));
form.append('0', createReadStream(FILE), {
  filename: 'tsconfig.json',
  contentType: 'application/json',
  knownLength: statSync(FILE).size,
});

const res = await fetch(SERVER, {
  method: 'POST',
  body: form,
  headers: { ...form.getHeaders(), 'apollo-require-preflight': 'true' },
});
const json = await res.json();
console.log(JSON.stringify(json, null, 2));
