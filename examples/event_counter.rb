# hartwell-lab-plugin: name=event-counter target=talus version=1.0.0
# Example Hartwell Labs plugin — counts events inside the talus host.
# Translate to Rust with: bin/labbridge r2rust examples/event_counter.rb

class EventCounter
  def init
    puts "event-counter online"
  end

  def handle_event(event)
    puts event
    event
  end

  def add(a, b)
    a + b
  end
end
