import React, { useState, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { Aperture, Microscope, Activity } from 'lucide-react';

import Webcam from "react-webcam";

type AppState = 'camera' | 'analyzing' | 'result';

const IMG_ANALYZING = "https://lh3.googleusercontent.com/aida-public/AB6AXuBLlu2z-9xZpknZUyg84ueHFU56V3GsBxXOkIatGh6GFIM861Z-hzQ_bbDcOsSiMYam0G-g7IPO5Bx-Or1fn2r8RJB8tvXbrfzhrXFOoYl0k4N1gpQImEWxbhExILOiLLb_IVXPujZeu7jriNq-kVFw80AF9t7jc33iC0_npQgKNjI4xV9CF3d5K2UPm58omACEe1O85H-0RPt3X8KzxdLWraT7iQA66d7fX0scKOQBk_QSerHXAkJgMAnrcKDpsSnvAmepwZisHeY";
const IMG_RESULT = "https://lh3.googleusercontent.com/aida-public/AB6AXuBrEBx6KywdOUY7JewDWBDftWH0Pwscxv1sfYr8nplT161TbSa4mIQxUtM0fF2VEcmHEWJfUD5VlvawnGx_dT6yaHzPiXbsbwcWf4vl32zXHeERXggw4eV4idw21H4QIYniJfyd1r9rDM9y25UZdU8MM-JJ1kpIT-Y1UMPqLpZFt2HEKZzNdxO2srn6maMXczjT4SoVlDsmKqPNyOeausWIm9W0A8wk44Y21HrojevRGwZr67cHfZs70wk7aUA2oM94_jEaVyeuMzM";

const CameraScreen = ({ onCapture, error }: { onCapture: (base64Img: string) => void, error: string | null, key?: string }) => {
  const webcamRef = useRef<Webcam>(null);

  const handleCaptureClick = () => {
    const imageSrc = webcamRef.current?.getScreenshot();
    if (imageSrc) {
      onCapture(imageSrc);
    } else {
      alert("错误：无法截取画面，请确保相机已开启");
    }
  };

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 z-0 flex flex-col"
    >
      {/* @ts-ignore: strictly typed react-webcam missing optional internal props */}
      <Webcam
        audio={false}
        muted={true}
        ref={webcamRef}
        screenshotFormat="image/jpeg"
        videoConstraints={{ facingMode: { ideal: "environment" } }}
        className="absolute inset-0 w-full h-full object-cover"
        onUserMediaError={(err) => {
          console.error("Camera error:", err);
          alert("无法访问相机: " + err);
        }}
        playsInline={true}
      />
      <div className="absolute inset-0 bg-[radial-gradient(circle,transparent_20%,rgba(14,14,14,0.6)_100%)]"></div>

      <header className="relative z-10 pt-16 px-8 flex justify-center">
        <h1 className="text-2xl font-bold tracking-widest drop-shadow-md text-white">
          测量食物卡路里
        </h1>
      </header>
      
      {error && (
        <div className="relative z-10 mt-4 mx-8 px-4 py-2 bg-red-500/80 text-white rounded-md text-center text-sm font-medium">
          {error}
        </div>
      )}

      <div className="relative z-10 mt-8 ml-8 flex flex-col gap-2 opacity-80">
        <div className="flex items-center gap-2">
          <div className="w-1.5 h-1.5 rounded-full bg-green-400 shadow-[0_0_8px_rgba(74,222,128,0.8)]"></div>
          <span className="text-[10px] tracking-[0.1em] uppercase text-white">AI 识别开启</span>
        </div>
        <div className="text-[10px] tracking-[0.1em] text-gray-300 uppercase">
          ISO AUTO &nbsp; ACTIVE
        </div>
      </div>

      <div className="flex-1 relative flex items-center justify-center p-8 z-10">
        <div className="w-full max-w-sm aspect-square border-2 border-dashed border-white/20 rounded-xl relative">
          <div className="absolute -top-1 -left-1 w-6 h-6 border-t-2 border-l-2 border-cyan-300 rounded-tl-lg"></div>
          <div className="absolute -top-1 -right-1 w-6 h-6 border-t-2 border-r-2 border-cyan-300 rounded-tr-lg"></div>
          <div className="absolute -bottom-1 -left-1 w-6 h-6 border-b-2 border-l-2 border-cyan-300 rounded-bl-lg"></div>
          <div className="absolute -bottom-1 -right-1 w-6 h-6 border-b-2 border-r-2 border-cyan-300 rounded-br-lg"></div>
          
          <motion.div 
            animate={{ top: ['0%', '100%', '0%'] }}
            transition={{ duration: 3, repeat: Infinity, ease: "linear" }}
            className="absolute left-0 w-full h-[2px] bg-gradient-to-r from-transparent via-cyan-300 to-transparent opacity-60"
          />
        </div>
      </div>

      <div className="absolute right-8 top-1/2 -translate-y-1/2 z-10">
        <div className="bg-black/60 backdrop-blur-xl p-4 rounded-xl border border-white/10 flex flex-col items-end">
          <span className="text-[10px] text-gray-400 uppercase mb-1">系统状态</span>
          <span className="text-cyan-300 font-bold text-lg">准备就绪</span>
        </div>
      </div>

      <main className="relative z-20 flex flex-col items-center pb-20 mt-auto">
        <div className="mb-10 px-6 py-2 bg-black/40 backdrop-blur-md rounded-full border border-white/10">
          <p className="text-gray-300 text-sm font-medium tracking-wide">
            将食物置于取景框中心
          </p>
        </div>

        <div className="relative flex items-center justify-center group cursor-pointer" onClick={handleCaptureClick}>
          <div className="absolute w-24 h-24 rounded-full border-4 border-cyan-300 transition-transform duration-300 group-active:scale-110"></div>
          <button className="w-16 h-16 bg-white rounded-full flex items-center justify-center transition-all duration-200 group-active:scale-90 shadow-[0_0_30px_rgba(255,255,255,0.3)] text-cyan-500">
            <Aperture size={32} />
          </button>
        </div>
      </main>
      
      <div className="absolute bottom-0 left-0 w-full h-40 bg-gradient-to-t from-black/80 to-transparent pointer-events-none z-0"></div>
    </motion.div>
  );
};

const AnalyzingScreen = ({ key }: { key?: string }) => {
  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 z-0 flex flex-col p-6 pt-16"
    >
      <img
        src={IMG_ANALYZING}
        alt="Analyzing"
        className="absolute inset-0 w-full h-full object-cover"
        referrerPolicy="no-referrer"
      />
      <div className="absolute inset-0 bg-gradient-to-t from-[#0e0e0e] via-transparent to-[#0e0e0e] opacity-80"></div>

      <div className="absolute inset-0 z-10 pointer-events-none flex flex-col items-center justify-center">
        <motion.div 
          animate={{ top: ['20%', '80%', '20%'] }}
          transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
          className="absolute left-0 w-full h-[2px] bg-gradient-to-r from-transparent via-cyan-300 to-transparent shadow-[0_0_15px_#81ecff]"
        />
        
        <div className="relative w-64 h-64 border-2 border-cyan-500/20 rounded-xl">
          <div className="absolute -top-1 -left-1 w-6 h-6 border-t-2 border-l-2 border-cyan-500"></div>
          <div className="absolute -top-1 -right-1 w-6 h-6 border-t-2 border-r-2 border-cyan-500"></div>
          <div className="absolute -bottom-1 -left-1 w-6 h-6 border-b-2 border-l-2 border-cyan-500"></div>
          <div className="absolute -bottom-1 -right-1 w-6 h-6 border-b-2 border-r-2 border-cyan-500"></div>
          
          <div className="absolute inset-0 flex items-center justify-center">
            <motion.div 
              animate={{ rotate: 360 }}
              transition={{ duration: 4, repeat: Infinity, ease: "linear" }}
              className="w-16 h-16 rounded-full border-2 border-dashed border-cyan-300/40 flex items-center justify-center"
            >
              <Aperture className="text-cyan-300" size={32} />
            </motion.div>
          </div>
        </div>
      </div>

      <div className="relative z-20 flex justify-between items-start w-full">
        <div className="space-y-1">
          <span className="uppercase tracking-widest text-cyan-500 text-xs font-semibold block">System Status</span>
          <h1 className="text-4xl font-extrabold tracking-tighter text-white">正在分析...</h1>
        </div>
        <div className="flex flex-col items-end">
          <span className="text-gray-400 text-xs mb-1">FPS: 60.0</span>
          <div className="w-32 h-1 bg-gray-800 rounded-full overflow-hidden">
            <motion.div 
              initial={{ width: '0%' }}
              animate={{ width: '100%' }}
              transition={{ duration: 2.5, ease: "easeInOut" }}
              className="h-full bg-cyan-300"
            />
          </div>
        </div>
      </div>

      <div className="relative z-20 grid grid-cols-12 gap-4 mt-auto mb-24">
        <div className="col-span-12 bg-black/60 backdrop-blur-xl py-3 px-6 rounded-full border border-white/10 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-cyan-500"></span>
              <span className="text-xs text-white">模型推理中</span>
            </div>
          </div>
          <span className="text-xs text-cyan-500 font-bold tracking-tighter">WAITING_RESPONSE</span>
        </div>
      </div>
    </motion.div>
  );
};

const ResultScreen = ({ onReturn, data }: { onReturn: () => void, data: any, key?: string }) => {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
      className="fixed inset-0 z-0 flex flex-col items-center justify-end min-h-screen p-6 pb-12"
    >
      <img
        src={IMG_RESULT}
        alt="Result"
        className="absolute inset-0 w-full h-full object-cover brightness-50 contrast-125"
        referrerPolicy="no-referrer"
      />
      <div className="absolute inset-0 bg-gradient-to-t from-[#0e0e0e] via-transparent to-transparent opacity-90"></div>

      <div className="relative z-20 bg-black/60 backdrop-blur-2xl bg-gradient-to-br from-cyan-300/10 to-cyan-500/5 w-full max-w-md rounded-2xl p-8 space-y-8 shadow-2xl border border-white/10">
        
        <div className="space-y-1">
          <div className="flex justify-between items-baseline">
            <span className="text-cyan-300 uppercase tracking-[0.05rem] text-xs font-semibold">检测到食物</span>
            <span className="text-gray-400 text-xs">AI 识别结果</span>
          </div>
          <h1 className="font-extrabold text-4xl tracking-tight text-white">{data?.name || '未知食物'}</h1>
        </div>

        <div className="flex flex-col items-center py-4">
          <span className="text-[5rem] leading-none font-black text-white tracking-tighter">{data?.calories || 0}</span>
          <span className="text-gray-400 font-medium text-lg mt-2">千卡</span>
        </div>

        <div className="grid grid-cols-3 gap-3">
          <div className="bg-white/5 rounded-xl p-4 flex flex-col items-center border border-white/5">
            <span className="text-gray-400 text-[10px] uppercase mb-1">蛋白质</span>
            <span className="text-xl font-bold text-green-400">{data?.protein || 0}g</span>
          </div>
          <div className="bg-white/5 rounded-xl p-4 flex flex-col items-center border border-white/5">
            <span className="text-gray-400 text-[10px] uppercase mb-1">碳水</span>
            <span className="text-xl font-bold text-cyan-300">{data?.carbs || 0}g</span>
          </div>
          <div className="bg-white/5 rounded-xl p-4 flex flex-col items-center border border-white/5">
            <span className="text-gray-400 text-[10px] uppercase mb-1">脂肪</span>
            <span className="text-xl font-bold text-blue-400">{data?.fat || 0}g</span>
          </div>
        </div>

        <div className="flex flex-col gap-3 pt-4">
          <button 
            className="w-full bg-cyan-300 text-black font-bold py-4 rounded-full text-lg shadow-[0_0_20px_rgba(103,232,249,0.3)] hover:scale-[0.98] transition-transform active:scale-95"
            onClick={onReturn}
          >
            保存并返回
          </button>
          <button 
            className="w-full bg-white/10 text-white font-medium py-4 rounded-full text-lg hover:bg-white/20 transition-colors"
            onClick={onReturn}
          >
            不保存直接返回
          </button>
        </div>
      </div>
    </motion.div>
  );
};

export default function App() {
  const [appState, setAppState] = useState<AppState>('camera');
  const [analysisResult, setAnalysisResult] = useState<any>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const handleCapture = async (base64Img: string) => {
    setAppState('analyzing');
    setErrorMsg(null);
    try {
      // 通过刚才配置的 vite proxy，相对路径 /api 会自动转发到 8000 端口
      const response = await fetch('/api/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ image: base64Img })
      });
      if (!response.ok) {
        throw new Error('API request failed: ' + response.statusText);
      }
      const data = await response.json();
      setAnalysisResult(data);
      setAppState('result');
    } catch (error: any) {
      console.error(error);
      setErrorMsg(error.message || "分析失败，请重试");
      setAppState('camera');
    }
  };

  return (
    <div className="bg-black text-white font-sans min-h-screen overflow-hidden relative selection:bg-cyan-500 selection:text-white">
      <AnimatePresence mode="wait">
        {appState === 'camera' && <CameraScreen key="camera" onCapture={handleCapture} error={errorMsg} />}
        {appState === 'analyzing' && <AnalyzingScreen key="analyzing" />}
        {appState === 'result' && <ResultScreen key="result" data={analysisResult} onReturn={() => setAppState('camera')} />}
      </AnimatePresence>
    </div>
  );
}
