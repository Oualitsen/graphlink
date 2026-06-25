package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.types.Bike
import dev.graphlink.test.generated.types.Car
import dev.graphlink.test.generated.types.VehicleDriver
import dev.graphlink.test.generated.types.VehicleOwner
import dev.graphlink.test.Fixtures.newRealClient
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*

// Cycle: VehicleDriver → Vehicle (Car|Bike) → VehicleOwner → VehicleDriver
//
// VehicleDriver is annotated @glExpand(depth: 3) in the schema, so the
// auto-generated query recurses 3 hops into the cycle:
//
//   layer 1 — VehicleDriver.vehicle          (Car or Bike)
//   layer 2 — Car/Bike.owner                 (VehicleOwner)
//   layer 3 — VehicleOwner.driver            (VehicleDriver, no vehicle selected)

class GlExpandTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    // ── layer 1: vehicle is selected ─────────────────────────────────────────

    @Nested
    inner class Layer1Vehicle {

        @Test
        fun vehicleDriver_hasCorrectId() = runTest {
            assertEquals("vd-1", client.queries.getVehicleDriver("vd-1").getVehicleDriver.id)
        }

        @Test
        fun vehicleDriver_hasCorrectName() = runTest {
            assertEquals("Alex Driver", client.queries.getVehicleDriver("vd-1").getVehicleDriver.name)
        }

        @Test
        fun vehicle_isNotNull() = runTest {
            assertNotNull(client.queries.getVehicleDriver("vd-1").getVehicleDriver.vehicle)
        }

        @Test
        fun vehicle_isCarForVd1() = runTest {
            assertIs<Car>(client.queries.getVehicleDriver("vd-1").getVehicleDriver.vehicle)
        }

        @Test
        fun car_hasCorrectModel() = runTest {
            val vehicle = client.queries.getVehicleDriver("vd-1").getVehicleDriver.vehicle
            assertEquals("Tesla Model 3", (vehicle as Car).model)
        }

        @Test
        fun vehicle_isBikeForVd2() = runTest {
            assertIs<Bike>(client.queries.getVehicleDriver("vd-2").getVehicleDriver.vehicle)
        }

        @Test
        fun bike_hasCorrectBrand() = runTest {
            val vehicle = client.queries.getVehicleDriver("vd-2").getVehicleDriver.vehicle
            assertEquals("Trek FX3", (vehicle as Bike).brand)
        }
    }

    // ── layer 2: owner is selected ───────────────────────────────────────────

    @Nested
    inner class Layer2Owner {

        @Test
        fun car_owner_isNotNull() = runTest {
            assertNotNull(client.queries.getVehicleDriver("vd-1").getVehicleDriver.vehicle?.owner)
        }

        @Test
        fun car_owner_hasCorrectId() = runTest {
            val owner: VehicleOwner? = client.queries.getVehicleDriver("vd-1").getVehicleDriver.vehicle?.owner
            assertEquals("vo-1", owner?.id)
        }

        @Test
        fun car_owner_hasCorrectName() = runTest {
            val owner: VehicleOwner? = client.queries.getVehicleDriver("vd-1").getVehicleDriver.vehicle?.owner
            assertEquals("Alice Owner", owner?.name)
        }

        @Test
        fun bike_owner_hasCorrectId() = runTest {
            val owner: VehicleOwner? = client.queries.getVehicleDriver("vd-2").getVehicleDriver.vehicle?.owner
            assertEquals("vo-2", owner?.id)
        }

        @Test
        fun bike_owner_hasCorrectName() = runTest {
            val owner: VehicleOwner? = client.queries.getVehicleDriver("vd-2").getVehicleDriver.vehicle?.owner
            assertEquals("Bob Owner", owner?.name)
        }
    }

    // ── layer 3: driver is selected ──────────────────────────────────────────

    @Nested
    inner class Layer3Driver {

        @Test
        fun owner_driver_isNotNull() = runTest {
            assertNotNull(client.queries.getVehicleDriver("vd-1").getVehicleDriver.vehicle?.owner?.driver)
        }

        @Test
        fun owner_driver_hasCorrectId() = runTest {
            val driver: VehicleDriver? = client.queries.getVehicleDriver("vd-1").getVehicleDriver.vehicle?.owner?.driver
            assertEquals("vd-1", driver?.id)
        }

        @Test
        fun owner_driver_hasCorrectName() = runTest {
            val driver: VehicleDriver? = client.queries.getVehicleDriver("vd-1").getVehicleDriver.vehicle?.owner?.driver
            assertEquals("Alex Driver", driver?.name)
        }
    }

    // ── layer 4: cycle truncated ──────────────────────────────────────────────

    @Nested
    inner class Layer4Truncated {

        @Test
        fun owner_driver_vehicle_isNull_forCar() = runTest {
            val inner: VehicleDriver? = client.queries.getVehicleDriver("vd-1")
                .getVehicleDriver.vehicle?.owner?.driver
            assertNull(inner?.vehicle)
        }

        @Test
        fun owner_driver_vehicle_isNull_forBike() = runTest {
            val inner: VehicleDriver? = client.queries.getVehicleDriver("vd-2")
                .getVehicleDriver.vehicle?.owner?.driver
            assertNull(inner?.vehicle)
        }
    }
}
