// Example Hartwell Labs Rust program (talus-style scoring heuristic).
// Translate with: bin/labbridge r2ruby examples/ransomware_score.rs --target talus

fn score_event(events: Vec<i64>, limit: i64) -> i64 {
    let mut total = 0;
    for e in events {
        total += e;
    }
    if total > limit {
        return total;
    }
    return 0;
}

fn verdict_for(pid: i64, score: i64) -> String {
    if score > 900 {
        return format!("pid {}: SIGKILL", pid);
    }
    if score > 500 {
        return format!("pid {}: alert", pid);
    }
    return format!("pid {}: benign", pid);
}

fn main() {
    let events = vec![300, 250, 420];
    let total = score_event(events, 900);
    println!("total={}", total);
    println!("{}", verdict_for(4242, total));
}
