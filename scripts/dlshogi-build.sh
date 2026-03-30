#!/bin/bash
# dlshogi 再ビルドスクリプト（EC2 インスタンス上で手動実行する）
# TensorRT 10.x 互換パッチ適用 → ビルド → モデル配置 → シンボリックリンク作成
# userdata.sh による初期セットアップ後のソース更新・再ビルドに使用する。
set -euxo pipefail

WORKDIR=/opt/DeepLearningShogi
ENGINE_DIR=/home/ubuntu/engines/dlshogi

# --- モデルのダウンロード元 (第31回世界コンピュータ将棋選手権版) ---
# model-dr2_exhi.zip は ZipCrypto 暗号化のため wcwc31 版を使用
MODEL_URL=https://github.com/TadaoYamaoka/DeepLearningShogi/releases/download/wcwc31/dlshogi_with_gct_wcsc31.zip
MODEL_ZIP=/tmp/dlshogi_wcwc31.zip
MODEL_ONNX=model-0000225kai.onnx
BOOK_BIN=book_model-0000223_225kai_4m.bin

# =====================================================================
# 1. 最新ソースに更新（パッチ済みファイルをリセット後に pull）
# =====================================================================
cd "$WORKDIR"
git checkout usi/nn_tensorrt.h usi/nn_tensorrt.cpp usi/Makefile
git pull --ff-only

# =====================================================================
# 2. TensorRT 10.x 互換パッチ適用
# =====================================================================
cat > "$WORKDIR/usi/nn_tensorrt.h" << 'PATCH_EOF'
#pragma once
#include "cppshogi.h"
#include "NvInferRuntimeCommon.h"
#include "NvInfer.h"
#include "NvOnnxParser.h"
#include "int8_calibrator.h"

struct InferDeleter
{
	template <typename T>
	void operator()(T* obj) const
	{
		if (obj)
		{
#if NV_TENSORRT_MAJOR >= 8
			delete obj;
#else
			obj->destroy();
#endif
		}
	}
};

template <typename T>
using InferUniquePtr = std::unique_ptr<T, InferDeleter>;

class NNTensorRT {
public:
	NNTensorRT(const char* filename, const int gpu_id, const int max_batch_size);
	~NNTensorRT();
	void forward(const int batch_size, packed_features1_t* x1, packed_features2_t* x2, DType* y1, DType* y2);
private:
	const int gpu_id;
	const int max_batch_size;
	InferUniquePtr<nvinfer1::ICudaEngine> engine;
	packed_features1_t* p1_dev;
	packed_features2_t* p2_dev;
	features1_t* x1_dev;
	features2_t* x2_dev;
	DType* y1_dev;
	DType* y2_dev;
	std::vector<void*> inputBindings;
#if NV_TENSORRT_MAJOR >= 10
	std::string outputNames[2];
#endif
	InferUniquePtr<nvinfer1::IExecutionContext> context;
	nvinfer1::Dims inputDims1;
	nvinfer1::Dims inputDims2;
	void load_model(const char* filename);
	void build(const std::string& onnx_filename);
};

typedef NNTensorRT NN;
PATCH_EOF

cat > "$WORKDIR/usi/nn_tensorrt.cpp" << 'PATCH_EOF'
#include "nn_tensorrt.h"
#include "cppshogi.h"
#include "unpack.h"

class Logger : public nvinfer1::ILogger
{
	const char* error_type(Severity severity)
	{
		switch (severity)
		{
		case Severity::kINTERNAL_ERROR: return "[F] ";
		case Severity::kERROR:          return "[E] ";
		case Severity::kWARNING:        return "[W] ";
		case Severity::kINFO:           return "[I] ";
		case Severity::kVERBOSE:        return "[V] ";
		default: assert(0); return "";
		}
	}
	void log(Severity severity, const char* msg) noexcept
	{
		if (severity == Severity::kINTERNAL_ERROR) {
			std::cerr << error_type(severity) << msg << std::endl;
		}
	}
} gLogger;

constexpr long long int operator"" _MiB(long long unsigned int val)
{
	return val * (1 << 20);
}

NNTensorRT::NNTensorRT(const char* filename, const int gpu_id, const int max_batch_size) : gpu_id(gpu_id), max_batch_size(max_batch_size)
{
	checkCudaErrors(cudaMalloc((void**)&p1_dev, sizeof(packed_features1_t) * max_batch_size));
	checkCudaErrors(cudaMalloc((void**)&p2_dev, sizeof(packed_features2_t) * max_batch_size));
	checkCudaErrors(cudaMalloc((void**)&x1_dev, sizeof(features1_t) * max_batch_size));
	checkCudaErrors(cudaMalloc((void**)&x2_dev, sizeof(features2_t) * max_batch_size));
	checkCudaErrors(cudaMalloc((void**)&y1_dev, MAX_MOVE_LABEL_NUM * (size_t)SquareNum * max_batch_size * sizeof(DType)));
	checkCudaErrors(cudaMalloc((void**)&y2_dev, max_batch_size * sizeof(DType)));
	inputBindings = { x1_dev, x2_dev, y1_dev, y2_dev };
	load_model(filename);
}

NNTensorRT::~NNTensorRT()
{
	checkCudaErrors(cudaFree(p1_dev));
	checkCudaErrors(cudaFree(p2_dev));
	checkCudaErrors(cudaFree(x1_dev));
	checkCudaErrors(cudaFree(x2_dev));
	checkCudaErrors(cudaFree(y1_dev));
	checkCudaErrors(cudaFree(y2_dev));
}

void NNTensorRT::build(const std::string& onnx_filename)
{
	auto builder = InferUniquePtr<nvinfer1::IBuilder>(nvinfer1::createInferBuilder(gLogger));
	if (!builder)
		throw std::runtime_error("createInferBuilder");

	const auto explicitBatch = 1U << static_cast<uint32_t>(nvinfer1::NetworkDefinitionCreationFlag::kEXPLICIT_BATCH);
	auto network = InferUniquePtr<nvinfer1::INetworkDefinition>(builder->createNetworkV2(explicitBatch));
	if (!network)
		throw std::runtime_error("createNetworkV2");

	auto config = InferUniquePtr<nvinfer1::IBuilderConfig>(builder->createBuilderConfig());
	if (!config)
		throw std::runtime_error("createBuilderConfig");

	auto parser = InferUniquePtr<nvonnxparser::IParser>(nvonnxparser::createParser(*network, gLogger));
	if (!parser)
		throw std::runtime_error("createParser");

	auto parsed = parser->parseFromFile(onnx_filename.c_str(), (int)nvinfer1::ILogger::Severity::kWARNING);
	if (!parsed)
		throw std::runtime_error("parseFromFile");

#if NV_TENSORRT_MAJOR < 10
	builder->setMaxBatchSize(max_batch_size);
	config->setMaxWorkspaceSize(64_MiB);
#else
	config->setMemoryPoolLimit(nvinfer1::MemoryPoolType::kWORKSPACE, 64_MiB);
#endif

	std::unique_ptr<nvinfer1::IInt8Calibrator> calibrator;
	if (builder->platformHasFastInt8())
	{
		std::string calibration_cache_filename = std::string(onnx_filename) + ".calibcache";
		std::ifstream calibcache(calibration_cache_filename);
		if (calibcache.is_open())
		{
			calibcache.close();
			config->setFlag(nvinfer1::BuilderFlag::kINT8);
			calibrator.reset(new Int8EntropyCalibrator2(onnx_filename.c_str(), 1));
			config->setInt8Calibrator(calibrator.get());
		}
		else if (builder->platformHasFastFp16())
		{
			config->setFlag(nvinfer1::BuilderFlag::kFP16);
		}
	}
	else if (builder->platformHasFastFp16())
	{
		config->setFlag(nvinfer1::BuilderFlag::kFP16);
	}

#ifdef FP16
	network->getInput(0)->setType(nvinfer1::DataType::kHALF);
	network->getInput(1)->setType(nvinfer1::DataType::kHALF);
	network->getOutput(0)->setType(nvinfer1::DataType::kHALF);
	network->getOutput(1)->setType(nvinfer1::DataType::kHALF);
#endif

	assert(network->getNbInputs() == 2);
	nvinfer1::Dims inputDims[] = { network->getInput(0)->getDimensions(), network->getInput(1)->getDimensions() };
	assert(inputDims[0].nbDims == 4);
	assert(inputDims[1].nbDims == 4);
	assert(network->getNbOutputs() == 2);

	auto profile = builder->createOptimizationProfile();
	const auto dims1 = inputDims[0].d;
	profile->setDimensions("input1", nvinfer1::OptProfileSelector::kMIN, nvinfer1::Dims4(1, dims1[1], dims1[2], dims1[3]));
	profile->setDimensions("input1", nvinfer1::OptProfileSelector::kOPT, nvinfer1::Dims4(max_batch_size, dims1[1], dims1[2], dims1[3]));
	profile->setDimensions("input1", nvinfer1::OptProfileSelector::kMAX, nvinfer1::Dims4(max_batch_size, dims1[1], dims1[2], dims1[3]));
	const auto dims2 = inputDims[1].d;
	profile->setDimensions("input2", nvinfer1::OptProfileSelector::kMIN, nvinfer1::Dims4(1, dims2[1], dims2[2], dims2[3]));
	profile->setDimensions("input2", nvinfer1::OptProfileSelector::kOPT, nvinfer1::Dims4(max_batch_size, dims2[1], dims2[2], dims2[3]));
	profile->setDimensions("input2", nvinfer1::OptProfileSelector::kMAX, nvinfer1::Dims4(max_batch_size, dims2[1], dims2[2], dims2[3]));
	config->addOptimizationProfile(profile);

#if NV_TENSORRT_MAJOR >= 8
	auto serializedEngine = InferUniquePtr<nvinfer1::IHostMemory>(builder->buildSerializedNetwork(*network, *config));
	if (!serializedEngine)
		throw std::runtime_error("buildSerializedNetwork");
	auto runtime = InferUniquePtr<nvinfer1::IRuntime>(nvinfer1::createInferRuntime(gLogger));
	engine.reset(runtime->deserializeCudaEngine(serializedEngine->data(), serializedEngine->size()));
	if (!engine)
		throw std::runtime_error("deserializeCudaEngine");
#else
	engine.reset(builder->buildEngineWithConfig(*network, *config));
	if (!engine)
		throw std::runtime_error("buildEngineWithConfig");
#endif
}

void NNTensorRT::load_model(const char* filename)
{
	std::string serialized_filename = std::string(filename) + "." + std::to_string(gpu_id) + "." + std::to_string(max_batch_size)
#ifdef FP16
		+ ".fp16"
#endif
		+ ".serialized";
	std::ifstream seriarizedFile(serialized_filename, std::ios::binary);
	if (seriarizedFile.is_open())
	{
		seriarizedFile.seekg(0, std::ios_base::end);
		const size_t modelSize = seriarizedFile.tellg();
		seriarizedFile.seekg(0, std::ios_base::beg);
		std::unique_ptr<char[]> blob(new char[modelSize]);
		seriarizedFile.read(blob.get(), modelSize);
		auto runtime = InferUniquePtr<nvinfer1::IRuntime>(nvinfer1::createInferRuntime(gLogger));
		engine = InferUniquePtr<nvinfer1::ICudaEngine>(runtime->deserializeCudaEngine(blob.get(), modelSize));
	}
	else
	{
		build(filename);

		auto serializedEngine = InferUniquePtr<nvinfer1::IHostMemory>(engine->serialize());
		if (!serializedEngine)
			throw std::runtime_error("Engine serialization failed");
		std::ofstream engineFile(serialized_filename, std::ios::binary);
		if (!engineFile)
			throw std::runtime_error("Cannot open engine file");
		engineFile.write(static_cast<char*>(serializedEngine->data()), serializedEngine->size());
		if (engineFile.fail())
			throw std::runtime_error("Cannot open engine file");
	}

	context = InferUniquePtr<nvinfer1::IExecutionContext>(engine->createExecutionContext());
	if (!context)
		throw std::runtime_error("createExecutionContext");

#if NV_TENSORRT_MAJOR >= 10
	inputDims1 = engine->getTensorShape("input1");
	inputDims2 = engine->getTensorShape("input2");
	outputNames[0].clear(); outputNames[1].clear();
	for (int i = 0; i < engine->getNbIOTensors(); ++i) {
		const char* tname = engine->getIOTensorName(i);
		if (engine->getTensorIOMode(tname) == nvinfer1::TensorIOMode::kOUTPUT) {
			if (outputNames[0].empty()) outputNames[0] = tname;
			else outputNames[1] = tname;
		}
	}
#else
	inputDims1 = engine->getBindingDimensions(0);
	inputDims2 = engine->getBindingDimensions(1);
#endif
}

void NNTensorRT::forward(const int batch_size, packed_features1_t* p1, packed_features2_t* p2, DType* y1, DType* y2)
{
	inputDims1.d[0] = batch_size;
	inputDims2.d[0] = batch_size;

	checkCudaErrors(cudaMemcpyAsync(p1_dev, p1, sizeof(packed_features1_t) * batch_size, cudaMemcpyHostToDevice, cudaStreamPerThread));
	checkCudaErrors(cudaMemcpyAsync(p2_dev, p2, sizeof(packed_features2_t) * batch_size, cudaMemcpyHostToDevice, cudaStreamPerThread));
	unpack_features1(batch_size, p1_dev, x1_dev, cudaStreamPerThread);
	unpack_features2(batch_size, p2_dev, x2_dev, cudaStreamPerThread);
#if NV_TENSORRT_MAJOR >= 10
	context->setInputShape("input1", inputDims1);
	context->setInputShape("input2", inputDims2);
	context->setTensorAddress("input1", x1_dev);
	context->setTensorAddress("input2", x2_dev);
	context->setTensorAddress(outputNames[0].c_str(), y1_dev);
	context->setTensorAddress(outputNames[1].c_str(), y2_dev);
	const bool status = context->enqueueV3(cudaStreamPerThread);
#else
	context->setBindingDimensions(0, inputDims1);
	context->setBindingDimensions(1, inputDims2);
	const bool status = context->enqueue(batch_size, inputBindings.data(), cudaStreamPerThread, nullptr);
#endif
	assert(status);
	checkCudaErrors(cudaMemcpyAsync(y1, y1_dev, sizeof(DType) * MAX_MOVE_LABEL_NUM * (size_t)SquareNum * batch_size, cudaMemcpyDeviceToHost, cudaStreamPerThread));
	checkCudaErrors(cudaMemcpyAsync(y2, y2_dev, sizeof(DType) * batch_size, cudaMemcpyDeviceToHost, cudaStreamPerThread));
	checkCudaErrors(cudaStreamSynchronize(cudaStreamPerThread));
}
PATCH_EOF

sed -i 's/ -lnvparsers//' "$WORKDIR/usi/Makefile"
chown -R ubuntu:ubuntu "$WORKDIR" || true

# =====================================================================
# 3. ビルド
# =====================================================================
mkdir -p "$ENGINE_DIR"
cd "$WORKDIR/usi"
make clean
make -j"$(nproc)" CC=g++
cp bin/usi "$ENGINE_DIR/dlshogi_usi"
chown -R ubuntu:ubuntu "$ENGINE_DIR"

echo ""
echo "=== ビルド・配置完了 ==="
echo "エンジン: $ENGINE_DIR/dlshogi_usi"

# =====================================================================
# 4. モデルファイル配置
# =====================================================================
if [ ! -f "$ENGINE_DIR/model.onnx" ]; then
  echo "=== モデルファイルをダウンロード ==="
  wget -q "$MODEL_URL" -O "$MODEL_ZIP"
  unzip -o "$MODEL_ZIP" "$MODEL_ONNX" "$BOOK_BIN" -d /tmp/model_extract/
  cp "/tmp/model_extract/$MODEL_ONNX" "$ENGINE_DIR/model.onnx"
  cp "/tmp/model_extract/$BOOK_BIN"   "$ENGINE_DIR/book.bin"
  chown ubuntu:ubuntu "$ENGINE_DIR/model.onnx" "$ENGINE_DIR/book.bin"
  rm -rf "$MODEL_ZIP" /tmp/model_extract/
else
  echo "=== モデルファイルは既に存在します: $ENGINE_DIR/model.onnx ==="
fi

# =====================================================================
# 5. シンボリックリンク作成（冪等）
# =====================================================================
ln -sf "$ENGINE_DIR/dlshogi_usi" /usr/local/bin/dlshogi_usi
ln -sf "$ENGINE_DIR/model.onnx"  /home/ubuntu/model.onnx
ln -sf "$ENGINE_DIR/book.bin"    /home/ubuntu/book.bin
chown -h ubuntu:ubuntu /home/ubuntu/model.onnx /home/ubuntu/book.bin || true

echo "モデル:   $ENGINE_DIR/model.onnx"
echo ""
echo "=== 起動確認 ==="
echo -e "usi\nquit" | dlshogi_usi
