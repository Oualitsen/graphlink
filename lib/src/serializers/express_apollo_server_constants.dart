const fileUploadType = '''export interface FileUpload {
  filename: string;
  mimetype: string;
  encoding: string;
  createReadStream(): NodeJS.ReadableStream;
}
''';

const graphqlUploadDeclarations = '''declare module 'graphql-upload/GraphQLUpload.mjs' {
  import { GraphQLScalarType } from 'graphql';
  const GraphQLUpload: GraphQLScalarType;
  export default GraphQLUpload;
}

declare module 'graphql-upload/graphqlUploadExpress.mjs' {
  import { RequestHandler } from 'express';
  function graphqlUploadExpress(options?: {
    maxFileSize?: number;
    maxFiles?: number;
  }): RequestHandler;
  export default graphqlUploadExpress;
}
''';

const graphLinkContextInterface =
    'export interface GraphLinkContext extends Record<string, unknown> {}\n';
