// Accept the same frame as JNI over stdin. Only the resulting proof goes to stdout.
use std::io::{Read, Write};
fn main() -> anyhow::Result<()> {
    let mut request = Vec::new();
    std::io::stdin().read_to_end(&mut request)?;
    let proof = mdwa_prover::prove(&request)?;
    eprintln!(
        "{} verified proof bytes, {} Vulkan transforms, {} MSMs, {} quotient divisions on {}",
        proof.len(),
        gpu::transforms(),
        gpu::multiscalars(),
        gpu::quotients(),
        gpu::adapter().map_err(anyhow::Error::msg)?
    );
    std::io::stdout().write_all(&proof)?;
    Ok(())
}
