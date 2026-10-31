import Foundation

// The checklists a technician can run on a job. These are on-device defaults: edit this one file
// to change them. They are not synced and an owner can't manage them from the web yet (that needs
// a server template store); the summary of a finished run is what reaches the server, as a job note.

struct ChecklistTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let items: [ChecklistItem]
}

struct ChecklistItem: Identifiable, Hashable {
    let id: String
    let label: String
    /// A value to write down with the tick, e.g. "Refrigerant pressure ___ psi".
    var reading: ChecklistReading? = nil
}

struct ChecklistReading: Hashable {
    let prompt: String
    let unit: String
}

enum ChecklistTemplates {
    static let all: [ChecklistTemplate] = [hvacService, plumbingRepair, electricalSafety, generalVisit]

    static func template(_ id: String) -> ChecklistTemplate? { all.first { $0.id == id } }

    static let hvacService = ChecklistTemplate(id: "hvac-service", title: "HVAC service", symbol: "fan", items: [
        ChecklistItem(id: "thermostat", label: "Thermostat calls for heat and cool"),
        ChecklistItem(id: "filter", label: "Air filter checked or replaced"),
        ChecklistItem(id: "coil", label: "Outdoor coil clean and clear"),
        ChecklistItem(id: "drain", label: "Condensate drain flushed and flowing"),
        ChecklistItem(id: "pressure-suction", label: "Suction pressure", reading: ChecklistReading(prompt: "Suction", unit: "psi")),
        ChecklistItem(id: "pressure-liquid", label: "Liquid line pressure", reading: ChecklistReading(prompt: "Liquid", unit: "psi")),
        ChecklistItem(id: "amps", label: "Compressor amp draw", reading: ChecklistReading(prompt: "Amp draw", unit: "A")),
        ChecklistItem(id: "capacitor", label: "Capacitor reading", reading: ChecklistReading(prompt: "Capacitor", unit: "µF")),
        ChecklistItem(id: "split", label: "Supply / return temperature split", reading: ChecklistReading(prompt: "Split", unit: "°F")),
        ChecklistItem(id: "electrical", label: "Electrical connections tight, no burn marks"),
    ])

    static let plumbingRepair = ChecklistTemplate(id: "plumbing-repair", title: "Plumbing repair", symbol: "drop", items: [
        ChecklistItem(id: "shutoff", label: "Main and fixture shut-offs located and working"),
        ChecklistItem(id: "pressure", label: "Static water pressure", reading: ChecklistReading(prompt: "Pressure", unit: "psi")),
        ChecklistItem(id: "leaks", label: "No leaks at the repair after 10 minutes"),
        ChecklistItem(id: "drains", label: "Drains run clear, no slow fixtures"),
        ChecklistItem(id: "water-heater-temp", label: "Water heater temperature", reading: ChecklistReading(prompt: "Temperature", unit: "°F")),
        ChecklistItem(id: "tpr", label: "T&P relief valve and discharge line OK"),
        ChecklistItem(id: "supply-lines", label: "Supply lines and valves under sinks inspected"),
        ChecklistItem(id: "cleanup", label: "Work area dry and cleaned up"),
    ])

    static let electricalSafety = ChecklistTemplate(id: "electrical-safety", title: "Electrical safety", symbol: "bolt", items: [
        ChecklistItem(id: "panel-label", label: "Panel labelled, cover and dead front in place"),
        ChecklistItem(id: "voltage", label: "Service voltage", reading: ChecklistReading(prompt: "Voltage", unit: "V")),
        ChecklistItem(id: "load", label: "Main load", reading: ChecklistReading(prompt: "Load", unit: "A")),
        ChecklistItem(id: "breakers", label: "No hot, buzzing or double-tapped breakers"),
        ChecklistItem(id: "gfci", label: "GFCI outlets trip and reset"),
        ChecklistItem(id: "afci", label: "AFCI breakers test"),
        ChecklistItem(id: "grounding", label: "Grounding and bonding present"),
        ChecklistItem(id: "smoke-co", label: "Smoke and CO alarms tested"),
    ])

    static let generalVisit = ChecklistTemplate(id: "general-visit", title: "General visit", symbol: "house", items: [
        ChecklistItem(id: "problem", label: "Confirmed the problem with the customer"),
        ChecklistItem(id: "protect", label: "Floors and work area protected"),
        ChecklistItem(id: "before", label: "Before photos taken"),
        ChecklistItem(id: "test", label: "Repair tested with the customer"),
        ChecklistItem(id: "after", label: "After photos taken"),
        ChecklistItem(id: "cleanup", label: "Work area cleaned up"),
    ])
}
