use std::collections::VecDeque;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc, Mutex, OnceLock,
};
use wgpu::util::DeviceExt;

struct TransformPlan {
    n: u32,
    root: [u8; 32],
    table: wgpu::Buffer,
    stages: Vec<(wgpu::ComputePipeline, wgpu::Buffer, u32)>,
}

struct Context {
    device: wgpu::Device,
    queue: wgpu::Queue,
    ntt: wgpu::ComputePipeline,
    tile: wgpu::ComputePipeline,
    quotient: wgpu::ComputePipeline,
    msm: wgpu::ComputePipeline,
    adapter: String,
    plans: VecDeque<Arc<TransformPlan>>,
}
static GPU: OnceLock<Result<Mutex<Context>, String>> = OnceLock::new();
static TRANSFORMS: AtomicUsize = AtomicUsize::new(0);
static MULTISCALARS: AtomicUsize = AtomicUsize::new(0);
static QUOTIENTS: AtomicUsize = AtomicUsize::new(0);

pub fn transforms() -> usize {
    TRANSFORMS.load(Ordering::Relaxed)
}
pub fn multiscalars() -> usize {
    MULTISCALARS.load(Ordering::Relaxed)
}
pub fn quotients() -> usize {
    QUOTIENTS.load(Ordering::Relaxed)
}
fn context() -> Result<std::sync::MutexGuard<'static, Context>, String> {
    GPU.get_or_init(|| pollster::block_on(Context::new()).map(Mutex::new))
        .as_ref()
        .map_err(Clone::clone)?
        .lock()
        .map_err(|_| "Vulkan device stopped".into())
}
pub fn adapter() -> Result<String, String> {
    Ok(context()?.adapter.clone())
}

impl Context {
    async fn new() -> Result<Self, String> {
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::VULKAN,
            ..Default::default()
        });
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions::default())
            .await
            .map_err(|e| format!("Vulkan compute adapter unavailable: {e}"))?;
        let info = adapter.get_info();
        if info.device_type == wgpu::DeviceType::Cpu {
            return Err("Hardware Vulkan compute unavailable".into());
        }
        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor {
                label: Some("MDWA prover"),
                required_limits: adapter.limits(),
                memory_hints: wgpu::MemoryHints::MemoryUsage,
                ..Default::default()
            })
            .await
            .map_err(|e| e.to_string())?;
        device.push_error_scope(wgpu::ErrorFilter::Validation);
        let pipeline = |field, main, entry| {
            let source = [field, include_str!("field.wgsl"), main].join("\n");
            let module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some(entry),
                source: wgpu::ShaderSource::Wgsl(source.into()),
            });
            device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some(entry),
                layout: None,
                module: &module,
                entry_point: Some(entry),
                compilation_options: Default::default(),
                cache: None,
            })
        };
        let ntt = pipeline(
            include_str!("fr.wgsl"),
            include_str!("ntt.wgsl"),
            "transform",
        );
        let tile = pipeline(
            include_str!("fr.wgsl"),
            include_str!("ntt.wgsl"),
            "transform_tile",
        );
        let quotient = pipeline(
            include_str!("fr.wgsl"),
            include_str!("ntt.wgsl"),
            "quotient",
        );
        let msm = pipeline(
            include_str!("fp.wgsl"),
            include_str!("msm.wgsl"),
            "sum_buckets",
        );
        if let Some(error) = device.pop_error_scope().await {
            return Err(error.to_string());
        }
        Ok(Self {
            device,
            queue,
            ntt,
            tile,
            quotient,
            msm,
            adapter: info.name,
            plans: VecDeque::new(),
        })
    }
    fn upload(&self, bytes: &[u8], usage: wgpu::BufferUsages) -> wgpu::Buffer {
        self.device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: None,
                contents: bytes,
                usage,
            })
    }
    fn buffer(&self, size: usize, usage: wgpu::BufferUsages) -> wgpu::Buffer {
        self.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: size as u64,
            usage,
            mapped_at_creation: false,
        })
    }
    fn run(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pipe: &wgpu::ComputePipeline,
        buffers: [&wgpu::Buffer; 4],
        groups: u32,
    ) -> Result<(), String> {
        if groups > self.device.limits().max_compute_workgroups_per_dimension
            || buffers
                .iter()
                .any(|b| b.size() > self.device.limits().max_storage_buffer_binding_size.into())
        {
            return Err("Proof exceeds Vulkan device limits".into());
        }
        let group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &pipe.get_bind_group_layout(0),
            entries: &std::array::from_fn::<_, 4, _>(|i| wgpu::BindGroupEntry {
                binding: i as u32,
                resource: buffers[i].as_entire_binding(),
            }),
        });
        let mut pass = encoder.begin_compute_pass(&Default::default());
        pass.set_pipeline(pipe);
        pass.set_bind_group(0, &group, &[]);
        pass.dispatch_workgroups(groups, 1, 1);
        Ok(())
    }
    fn read(
        &self,
        mut encoder: wgpu::CommandEncoder,
        source: &wgpu::Buffer,
        dst: &mut [u8],
    ) -> Result<(), String> {
        let readback = self.buffer(
            dst.len(),
            wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        );
        encoder.copy_buffer_to_buffer(source, 0, &readback, 0, dst.len() as u64);
        let submission = self.queue.submit([encoder.finish()]);
        let (tx, rx) = std::sync::mpsc::sync_channel(1);
        readback
            .slice(..)
            .map_async(wgpu::MapMode::Read, move |status| {
                let _ = tx.send(status);
            });
        self.device
            .poll(wgpu::PollType::WaitForSubmissionIndex(submission))
            .map_err(|e| e.to_string())?;
        rx.recv()
            .map_err(|e| e.to_string())?
            .map_err(|e| e.to_string())?;
        dst.copy_from_slice(&readback.slice(..).get_mapped_range());
        readback.unmap();
        Ok(())
    }

    fn transform_plan(
        &mut self,
        n: u32,
        root: [u8; 32],
        make_roots: impl FnOnce() -> Vec<u8>,
    ) -> Result<Arc<TransformPlan>, String> {
        if let Some(plan) = self
            .plans
            .iter()
            .find(|plan| plan.n == n && plan.root == root)
        {
            return Ok(Arc::clone(plan));
        }
        let roots = make_roots();
        if roots.len() as u64 != u64::from(n) * 16 {
            return Err("Invalid NTT roots".into());
        }
        let mut stages = Vec::new();
        let mut stage = |pipeline: &wgpu::ComputePipeline, width: u32, groups| {
            let params = self.upload(
                &[n.to_le_bytes(), width.to_le_bytes()].concat(),
                wgpu::BufferUsages::UNIFORM,
            );
            stages.push((pipeline.clone(), params, groups));
        };
        let mut width = 1;
        while n / width >= 128 {
            stage(&self.tile, width, n / 128);
            width *= 128;
        }
        while width < n {
            stage(&self.ntt, width, (n / 2).div_ceil(64));
            width *= 2;
        }
        let plan = Arc::new(TransformPlan {
            n,
            root,
            stages,
            table: self.upload(&roots, wgpu::BufferUsages::STORAGE),
        });
        // Keep at most 4 MiB of public twiddle tables. Witness buffers stay per call.
        if roots.len() <= 1 << 20 {
            if self.plans.len() == 4 {
                self.plans.pop_front();
            }
            self.plans.push_back(Arc::clone(&plan));
        }
        Ok(plan)
    }
}

pub fn ntt(
    data: &mut [u8],
    log_n: u32,
    root: [u8; 32],
    make_roots: impl FnOnce() -> Vec<u8>,
) -> Result<(), String> {
    let n = 1u32.checked_shl(log_n).ok_or("Invalid NTT length")?;
    if data.len() as u64 != u64::from(n) * 32 {
        return Err("Invalid NTT length".into());
    }
    let mut ctx = context()?;
    let plan = ctx.transform_plan(n, root, make_roots)?;
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    let buffers = [ctx.upload(data, usage), ctx.buffer(data.len(), usage)];
    let mut encoder = ctx.device.create_command_encoder(&Default::default());
    let mut src = 0;
    for (pipe, params, groups) in &plan.stages {
        ctx.run(
            &mut encoder,
            pipe,
            [&buffers[src], &buffers[1 - src], &plan.table, params],
            *groups,
        )?;
        src = 1 - src;
    }
    ctx.read(encoder, &buffers[src], data)?;
    TRANSFORMS.fetch_add(1, Ordering::Relaxed);
    Ok(())
}

pub fn divide_vanishing(data: &mut [u8], factors: &[u8]) -> Result<(), String> {
    let ctx = context()?;
    let storage = wgpu::BufferUsages::STORAGE;
    let input = ctx.upload(data, storage);
    let output = ctx.buffer(data.len(), storage | wgpu::BufferUsages::COPY_SRC);
    let table = ctx.upload(factors, storage);
    let n = (data.len() / 32) as u32;
    let count = (factors.len() / 32) as u32;
    let params = ctx.upload(
        &[n.to_le_bytes(), count.to_le_bytes()].concat(),
        wgpu::BufferUsages::UNIFORM,
    );
    let mut encoder = ctx.device.create_command_encoder(&Default::default());
    ctx.run(
        &mut encoder,
        &ctx.quotient,
        [&input, &output, &table, &params],
        n.div_ceil(64),
    )?;
    ctx.read(encoder, &output, data)?;
    QUOTIENTS.fetch_add(1, Ordering::Relaxed);
    Ok(())
}

// One unsigned byte per base. A GPU invocation sums up to 32 bases in one bucket.
pub fn msm_buckets(points: &[u8], digits: &[u8]) -> Result<(Vec<usize>, Vec<u8>), String> {
    let mut buckets = vec![Vec::new(); 255];
    for (i, &digit) in digits.iter().enumerate() {
        if digit != 0 {
            buckets[usize::from(digit) - 1].push(i as u32);
        }
    }
    let mut jobs = Vec::new();
    let mut indices = Vec::new();
    let mut destinations = Vec::new();
    for (bucket, points) in buckets.into_iter().enumerate() {
        for run in points.chunks(32) {
            destinations.push(bucket);
            jobs.extend_from_slice(&((indices.len() / 4) as u32).to_le_bytes());
            jobs.extend_from_slice(&(run.len() as u32).to_le_bytes());
            for index in run {
                indices.extend_from_slice(&index.to_le_bytes());
            }
        }
    }
    let mut result = vec![0u8; destinations.len() * 144];
    if !jobs.is_empty() {
        let ctx = context()?;
        let storage = wgpu::BufferUsages::STORAGE;
        let bases = ctx.upload(points, storage);
        let ids = ctx.upload(&indices, storage);
        let work = ctx.upload(&jobs, storage);
        let output = ctx.buffer(result.len(), storage | wgpu::BufferUsages::COPY_SRC);
        let mut encoder = ctx.device.create_command_encoder(&Default::default());
        ctx.run(
            &mut encoder,
            &ctx.msm,
            [&bases, &ids, &work, &output],
            (destinations.len() as u32).div_ceil(32),
        )?;
        ctx.read(encoder, &output, &mut result)?;
        MULTISCALARS.fetch_add(1, Ordering::Relaxed);
    }
    Ok((destinations, result))
}
