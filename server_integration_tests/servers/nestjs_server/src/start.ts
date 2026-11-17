import 'reflect-metadata';
import './impl/my-context.js';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module.js';

const PORT = 9926;

const app = await NestFactory.create(AppModule, { rawBody: true, logger: ['error', 'warn'] });
app.enableCors();
await app.listen(PORT);
console.log(`Server ready at http://localhost:${PORT}/graphql`);
