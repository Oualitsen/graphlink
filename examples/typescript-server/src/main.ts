import { createServer } from './generated/index.js';
import { MyVehicleService } from './impl/MyVehicleService.js';
import { MyOwnerService } from './impl/MyOwnerService.js';
import { MyVehicleSchemaMappingsService } from './impl/MyVehicleSchemaMappingsService.js';
import { MyOwnerGuard } from './impl/MyOwnerGuard.js';
import { MyUploadResultService } from './impl/MyUploadResultService.js';
const app = await createServer({
  vehicleService: new MyVehicleService(),
  ownerService: new MyOwnerService(),
  vehicleSchemaMappingsService: new MyVehicleSchemaMappingsService(),
  ownerGuard: new MyOwnerGuard(),
  uploadResultService: new MyUploadResultService(),
});

app.listen(4000, () => console.log('GraphQL ready at http://localhost:4000/graphql'));
