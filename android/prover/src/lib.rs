use anyhow::{Context, Result, anyhow, ensure};
use crypto::proofs as current;
use crypto_old::proofs as legacy;
use serialize::{peek_tag, tagged_deserialize, tagged_serialize};
use std::{
    io::{self, Cursor},
    sync::Mutex,
};

struct Material<'a> {
    location: &'a str,
    ir: &'a [u8],
    pk: &'a [u8],
    vk: &'a [u8],
    params: &'a [u8],
}

// Both generations use the same wire material. Keep the SDK's version-specific
// parameter readers and proving-key deserializers.
macro_rules! providers {
    ($p:ident) => {
        impl $p::ParamsProverProvider for Material<'_> {
            async fn get_params(&self, k: u8) -> io::Result<$p::ParamsProver> {
                if self.params.get(..4) != Some(&u32::from(k).to_le_bytes()) {
                    return Err(io::Error::other("Public parameters have incorrect degree"));
                }
                $p::ParamsProver::read(self.params)
            }
        }
        impl $p::Resolver for Material<'_> {
            async fn resolve_key(
                &self,
                key: $p::KeyLocation,
            ) -> io::Result<Option<$p::ProvingKeyMaterial>> {
                Ok((key.0 == self.location).then(|| $p::ProvingKeyMaterial {
                    prover_key: self.pk.to_vec(),
                    verifier_key: self.vk.to_vec(),
                    ir_source: self.ir.to_vec(),
                }))
            }
        }
    };
}
providers!(current);
providers!(legacy);

fn part<'a>(frame: &mut &'a [u8]) -> Result<&'a [u8]> {
    let (size, rest) = frame.split_at_checked(4).context("Missing field length")?;
    let (field, tail) = rest
        .split_at_checked(u32::from_le_bytes(size.try_into()?) as usize)
        .context("Truncated proof request")?;
    *frame = tail;
    Ok(field)
}

pub fn prove(mut frame: &[u8]) -> Result<Vec<u8>> {
    // Job-level accounting covers the Rayon workers the upstream prover starts.
    static JOB: Mutex<()> = Mutex::new(());
    let _job = JOB.lock().unwrap_or_else(|e| e.into_inner());
    let location = std::str::from_utf8(part(&mut frame)?)?;
    let mut preimage: current::ProofPreimage = tagged_deserialize(part(&mut frame)?)?;
    ensure!(
        preimage.key_location.0 == location,
        "Circuit location mismatch"
    );
    let binding = part(&mut frame)?;
    if !binding.is_empty() {
        ensure!(binding.len() == 32, "Bad binding length");
        preimage.binding_input =
            crypto::curve::Fr::from_le_bytes(binding).context("Invalid proof binding")?;
    }
    let material = Material {
        location,
        ir: part(&mut frame)?,
        pk: part(&mut frame)?,
        vk: part(&mut frame)?,
        params: part(&mut frame)?,
    };
    ensure!(frame.is_empty(), "Trailing proof request");
    gpu::adapter().map_err(|e| anyhow!(e))?;
    let before = gpu::transforms();
    let rng = rand::rngs::OsRng;
    let mut output = Vec::new();
    match peek_tag(&mut Cursor::new(material.vk))?.as_str() {
        "verifier-key[v6]" => {
            let old = zkir2::ir_v1::preimage_to_v1(&preimage);
            let (proof, _) =
                pollster::block_on(old.prove::<zkir2::IrSource>(rng, &material, &material))?;
            tagged_serialize(&proof, &mut output)?;
        }
        "verifier-key[v7]" if material.ir.starts_with(b"midnight:ir-source[v3-generic]:") => {
            let (proof, _) =
                pollster::block_on(preimage.prove::<zkir3::IrSource>(rng, &material, &material))?;
            tagged_serialize(&proof, &mut output)?;
        }
        "verifier-key[v7]" => {
            let (proof, _) =
                pollster::block_on(preimage.prove::<zkir2::IrSource>(rng, &material, &material))?;
            tagged_serialize(&proof, &mut output)?;
        }
        _ => anyhow::bail!("Unsupported verifier key version"),
    }
    ensure!(
        gpu::transforms() > before,
        "Proof completed without a Vulkan transform"
    );
    Ok(output)
}

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_burgesstg_mdwa_NativeProver_prove(
    mut env: jni::JNIEnv,
    _: jni::objects::JClass,
    frame: jni::objects::JByteArray,
) -> jni::sys::jbyteArray {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| -> Result<_> {
        let bytes = env.convert_byte_array(frame)?;
        let proof = prove(&bytes)?;
        Ok(env.byte_array_from_slice(&proof)?.into_raw())
    }));
    match result {
        Ok(Ok(proof)) => proof,
        _ => {
            // Upstream diagnostics may contain witness material.
            let _ = env.throw_new(
                "java/lang/IllegalStateException",
                "Local Vulkan proof failed",
            );
            std::ptr::null_mut()
        }
    }
}
