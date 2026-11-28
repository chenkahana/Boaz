import Testing
@testable import BoazKit

@Suite("Spinner gate")
struct SpinnerGateTests {
    @Test func fastLoadNeverShowsASpinner() {
        var gate = SpinnerGate()
        gate.setLoading(true, at: 0)
        #expect(!gate.isVisible(at: 0.1))
        gate.setLoading(false, at: 0.19)
        #expect(!gate.isVisible(at: 0.19))
        #expect(!gate.isVisible(at: 1))
        #expect(gate.nextChange(at: 1) == nil)
    }

    @Test func slowLoadShowsAfterTheDelay() {
        var gate = SpinnerGate()
        gate.setLoading(true, at: 0)
        #expect(!gate.isVisible(at: 0.199))
        #expect(gate.nextChange(at: 0.1).map { abs($0 - 0.1) < 1e-9 } == true)
        #expect(gate.isVisible(at: 0.2))
        #expect(gate.isVisible(at: 5))
        #expect(gate.nextChange(at: 5) == nil)
    }

    @Test func shownSpinnerHoldsForTheMinimumThenHides() {
        var gate = SpinnerGate()
        gate.setLoading(true, at: 0)
        #expect(gate.isVisible(at: 0.25))      // shown from 0.2
        gate.setLoading(false, at: 0.25)       // load ends 50 ms after it appeared
        #expect(gate.isVisible(at: 0.25))
        #expect(gate.isVisible(at: 0.49))
        #expect(gate.nextChange(at: 0.25).map { abs($0 - 0.25) < 1e-9 } == true)
        #expect(!gate.isVisible(at: 0.5))
        #expect(gate.nextChange(at: 0.5) == nil)
    }

    @Test func loadAfterTheMinimumHidesImmediately() {
        var gate = SpinnerGate()
        gate.setLoading(true, at: 0)
        #expect(gate.isVisible(at: 1))
        gate.setLoading(false, at: 1)
        #expect(!gate.isVisible(at: 1))
    }

    @Test func restartedLoadWhileHeldKeepsTheSpinner() {
        var gate = SpinnerGate()
        gate.setLoading(true, at: 0)
        #expect(gate.isVisible(at: 0.3))
        gate.setLoading(false, at: 0.3)
        gate.setLoading(true, at: 0.35)
        #expect(gate.isVisible(at: 0.6))
        #expect(gate.nextChange(at: 0.6) == nil)
    }

    @Test func eachLoadStartsItsOwnDelay() {
        var gate = SpinnerGate()
        gate.setLoading(true, at: 0)
        gate.setLoading(false, at: 0.1)
        gate.setLoading(true, at: 10)
        #expect(!gate.isVisible(at: 10.1))
        #expect(gate.isVisible(at: 10.2))
    }
}
