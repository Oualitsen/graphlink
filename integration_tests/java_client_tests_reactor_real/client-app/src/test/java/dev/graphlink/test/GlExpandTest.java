package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.interfaces.Vehicle;
import dev.graphlink.test.generated.types.Bike;
import dev.graphlink.test.generated.types.Car;
import dev.graphlink.test.generated.types.VehicleDriver;
import dev.graphlink.test.generated.types.VehicleOwner;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

// Cycle: VehicleDriver → Vehicle (Car|Bike) → VehicleOwner → VehicleDriver
//
// VehicleDriver is annotated @glExpand(depth: 3) in the schema, so the
// auto-generated query recurses 3 hops into the cycle:
//
//   layer 1 — VehicleDriver.vehicle          (Car or Bike)
//   layer 2 — Car/Bike.owner                 (VehicleOwner)
//   layer 3 — VehicleOwner.driver            (VehicleDriver, no vehicle selected)

class GlExpandTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    // ── layer 1: vehicle is selected ─────────────────────────────────────────

    @Nested
    class Layer1Vehicle {

        @Test
        void vehicleDriver_hasCorrectId() {
            VehicleDriver vd = client.queries.getVehicleDriver("vd-1").block().getGetVehicleDriver();
            assertEquals("vd-1", vd.getId());
        }

        @Test
        void vehicleDriver_hasCorrectName() {
            VehicleDriver vd = client.queries.getVehicleDriver("vd-1").block().getGetVehicleDriver();
            assertEquals("Alex Driver", vd.getName());
        }

        @Test
        void vehicle_isNotNull() {
            VehicleDriver vd = client.queries.getVehicleDriver("vd-1").block().getGetVehicleDriver();
            assertNotNull(vd.getVehicle());
        }

        @Test
        void vehicle_isCarForVd1() {
            Vehicle vehicle = client.queries.getVehicleDriver("vd-1").block().getGetVehicleDriver().getVehicle();
            assertInstanceOf(Car.class, vehicle);
        }

        @Test
        void car_hasCorrectModel() {
            Vehicle vehicle = client.queries.getVehicleDriver("vd-1").block().getGetVehicleDriver().getVehicle();
            assertEquals("Tesla Model 3", ((Car) vehicle).getModel());
        }

        @Test
        void vehicle_isBikeForVd2() {
            Vehicle vehicle = client.queries.getVehicleDriver("vd-2").block().getGetVehicleDriver().getVehicle();
            assertInstanceOf(Bike.class, vehicle);
        }

        @Test
        void bike_hasCorrectBrand() {
            Vehicle vehicle = client.queries.getVehicleDriver("vd-2").block().getGetVehicleDriver().getVehicle();
            assertEquals("Trek FX3", ((Bike) vehicle).getBrand());
        }
    }

    // ── layer 2: owner is selected ───────────────────────────────────────────

    @Nested
    class Layer2Owner {

        @Test
        void car_owner_isNotNull() {
            Vehicle vehicle = client.queries.getVehicleDriver("vd-1").block().getGetVehicleDriver().getVehicle();
            assertNotNull(vehicle.getOwner());
        }

        @Test
        void car_owner_hasCorrectId() {
            VehicleOwner owner = client.queries.getVehicleDriver("vd-1").block().getGetVehicleDriver().getVehicle().getOwner();
            assertEquals("vo-1", owner.getId());
        }

        @Test
        void car_owner_hasCorrectName() {
            VehicleOwner owner = client.queries.getVehicleDriver("vd-1").block().getGetVehicleDriver().getVehicle().getOwner();
            assertEquals("Alice Owner", owner.getName());
        }

        @Test
        void bike_owner_hasCorrectId() {
            VehicleOwner owner = client.queries.getVehicleDriver("vd-2").block().getGetVehicleDriver().getVehicle().getOwner();
            assertEquals("vo-2", owner.getId());
        }

        @Test
        void bike_owner_hasCorrectName() {
            VehicleOwner owner = client.queries.getVehicleDriver("vd-2").block().getGetVehicleDriver().getVehicle().getOwner();
            assertEquals("Bob Owner", owner.getName());
        }
    }

    // ── layer 3: driver is selected ──────────────────────────────────────────

    @Nested
    class Layer3Driver {

        @Test
        void owner_driver_isNotNull() {
            VehicleOwner owner = client.queries.getVehicleDriver("vd-1").block().getGetVehicleDriver().getVehicle().getOwner();
            assertNotNull(owner.getDriver());
        }

        @Test
        void owner_driver_hasCorrectId() {
            VehicleOwner owner = client.queries.getVehicleDriver("vd-1").block().getGetVehicleDriver().getVehicle().getOwner();
            assertEquals("vd-1", owner.getDriver().getId());
        }

        @Test
        void owner_driver_hasCorrectName() {
            VehicleOwner owner = client.queries.getVehicleDriver("vd-1").block().getGetVehicleDriver().getVehicle().getOwner();
            assertEquals("Alex Driver", owner.getDriver().getName());
        }
    }

    // ── layer 4: cycle truncated ──────────────────────────────────────────────

    @Nested
    class Layer4Truncated {

        @Test
        void owner_driver_vehicle_isNull_forCar() {
            VehicleDriver inner = client.queries.getVehicleDriver("vd-1").block()
                    .getGetVehicleDriver().getVehicle().getOwner().getDriver();
            assertNull(inner.getVehicle());
        }

        @Test
        void owner_driver_vehicle_isNull_forBike() {
            VehicleDriver inner = client.queries.getVehicleDriver("vd-2").block()
                    .getGetVehicleDriver().getVehicle().getOwner().getDriver();
            assertNull(inner.getVehicle());
        }
    }
}
