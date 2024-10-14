(
s.waitForBoot({
	var inputs, master;
	var numInputs, toggleInput;
	var voxaGroup, masterBus;
	var win, stackLayout, mainView, saveOverlay, loadOverlay, title, style, textStyle;
	var saveView, saveText, saveInput, closeSaveButton, doSaveButton;
	var loadView, loadText, closeLoadButton, fileSelector, loadFile;
	var fullScreen, getLabel, folderName, assets, margins, mainColor;
	var loadButton, saveButton, saveAsButton, fileView;
	var load, save, saveAs, currentFile;
	var percentFunc;
	var mute, quit, synthFree, resizeFunc;
	var inputsLayout, inputsView, inputsButtons;
	var setHPFreq, setHPGate, setLPFreq, setLPGate, setBRFFreq, setBRFGate;
	var hpButton, hpSlider, lpButton, lpSlider, brfButton, brfSlider, filterView;
	var setResoNote, setResoMul, setResoAmount, setResoAmp, notes, freqs;
	var resoAmountSlider, resoNoteSelector, resoMulSelector, resoAmpSlider, resoView;
	var setResoHarmoFB, resoHarmoFB, setResoHarmoMix, resoHarmoMixer;
	var setEchoAmount, setEchoBPM, setEchoMul, setEchoAmp;
	var echoAmountSlider, echoTapTempo, echoMulSelector, echoMulState, echoAmpSlider, echoView;
	var playRoutine, echoRoutine, echoClock;
	var setReverbAmount, setReverbDur, reverbDryWetSlider, reverbDurSlider, reverbView;
	var setDryAmp, dryAmpSlider, dryAmpView, setAmp, ampSlider, ampView;
	var state;

	// Variables assign.
	folderName = thisProcess.nowExecutingPath.dirname;
	assets = folderName ++ "/assets/";
	fullScreen = false;
	margins = 6;
	mainColor = Color.fromHexString("#7c48bf");
	synthFree = false;
	numInputs = s.options.numInputBusChannels;
	inputsButtons = List(0);
	inputs = Array.fill(numInputs, { nil });
	notes = [
		"C", "Db", "D", "Eb",
		"E", "F", "F#", "G", "Ab",
		"A", "Bb", "B"
	];
	freqs = Scale.at(\chromatic).ratios * 24.midicps;
	currentFile = nil;

	state = (
		hpFreq: 40,
		hpGate: 1,
		lpFreq: 13000,
		lpGate: 1,
		brfFreq: 300,
		brfGate: 0,
		resoAmount: 0,
		resoNote: 0,
		resoMul: 1,
		resoAmp: 0.1,
		resoHarmoFB: Array.fill(9, { 1 }),
		resoHarmoMix: Array.fill(9, { |i| 1/(i + 1) }),
		echoAmount: 0,
		echoBPM: 60,
		echoMul: 1,
		echoAmp: 0.25,
		reverbDryWet: 0,
		reverbDur: 0.25,
		dryAmp: 1,
		amp: 0.8,
	);

	// Synths setup
	voxaGroup = Group.after(s.defaultGroup.nodeID);
	fork {
		masterBus = Bus.audio(s, 1);
		s.sync;
		SynthDef(\voxaIn, { |out = 0, inChannel = 0|
			var snd = SoundIn.ar(inChannel);
			Out.ar(out, snd);
		}).add;
		// Master synth
		master = SynthDef(\voxaMaster, { |out = 0, amp = 1, inBus,
			hpGate = 1, hpFreq = 40, lpGate = 1, lpFreq = 12000,
			brfGate = 0, brfFreq = 300,
			dryAmp = 1,
			resFreq = 220, resDecay = 0.99, resAmp = 0.25,
			echoDecay = 0, echoDur = 1, echoAmp = 0.5,
			reverbDryWet = 0, reverbDur = 0.1|

			var snd, envGen;
			var local, resoSource, resoFB, resTime, resoMix;
			var resoSources = Array.fill(9, { 0 });
			var resoFBs = Array.fill(9, { 0 });
			var resAmps = NamedControl.kr(
				\resAmps,
				[1, 1/2, 1/3, 1/4, 1/5, 1/6, 1/7, 1/8, 1/9]
			);
			var resFBs = NamedControl.kr(
				\resFBs,
				[1, 1, 1, 1, 1, 1, 1, 1, 1]
			);
			var echo, echoMix;
			var reverb;

			// Get sound (mono)
			snd = In.ar(inBus, 1);

			// Filter out unwanted frequencies
			snd = Lag.kr(hpGate, 0.1).if(
				HPF.ar(snd, hpFreq),
				snd
			);
			snd = Lag.kr(lpGate, 0.1).if(
				LPF.ar(snd, lpFreq),
				snd
			);
			snd = Lag.kr(brfGate, 0.1).if(
				BRF.ar(snd, brfFreq, 1),
				snd
			);

			// Get feedback
			local = LocalIn.ar(10);

			// Calculate resonance harmonics (mono)
			9.do({ |index|
				resoSources[index] = snd + local[index];
				// This compander mitigates the
				// self-sustained feedback
				// of phase synced signals
				resoSources[index] = Compander.ar(
					resoSources[index],
					resoSources[index],
					0.4,
					1.0,
					1/3,
					0.005
				);
				resoFBs[index] = DelayC.ar(
					resoSources[index],
					0.2,
					(resFreq * (index + 1)).reciprocal - ControlRate.ir.reciprocal,
					resFBs[index]
				);
				resoFBs[index] = resoFBs[index] * resDecay;
			});

			// Mix resonances
			resoMix = Mix.ar([
				local[0] * resAmps[0], local[1] * resAmps[1], local[2] * resAmps[2],
				local[3] * resAmps[3], local[4] * resAmps[4], local[5] * resAmps[5],
				local[6] * resAmps[6], local[7] * resAmps[7], local[8] * resAmps[8]
			]);
			resoMix = resoMix * resAmp;

			snd = snd * dryAmp;

			// Echo (mono)
			echo = DelayC.ar(
				(snd + resoMix + local[9]),
				8.0,
				(echoDur - ControlRate.ir.reciprocal)
			);
			echo = echo * echoDecay;
			echoMix = local[9] * echoAmp;

			// Send feedback
			LocalOut.ar((resoFBs ++ [echo]));

			// Mix
			snd = snd + resoMix + echoMix;

			// Reverb
			reverb = snd;
			4.do({ reverb = AllpassC.ar(
				// Update max if needed
				reverb,
				0.05,
				{ Rand(0.001, 0.05) }.dup,
				reverbDur
			) });
			snd = reverbDryWet.if(
				reverb,
				snd
			);

			// Synth Master
			snd = snd * amp;

			// Clean up & safety
			snd = LeakDC.ar(snd);
			snd = Limiter.ar(snd, amp);

			Out.ar(out, snd);
		}).play(
			voxaGroup,
			[
				\inBus, masterBus,
				\hpFreq, state[\hpFreq],
				\hpGate, state[\hpGate],
				\lpFreq, state[\lpFreq],
				\lpGate, state[\lpGate],
				\brfFreq, state[\brfFreq],
				\brfGate, state[\brfGate],
				\resDecay, state[\resoAmount],
				\resFreq, (freqs[state[\resoNote]] * state[\resoMul]),
				\resAmp, state[\resoAmp],
				\resAmps, state[\resHarmoMix],
				\resFBs, state[\resHarmoFB],
				\echoDecay, state[\echoAmount],
				\echoDur, ((60 / state[\echoBPM]) * state[\echoMul]),
				\echoAmp, state[\echoAmp],
				\reverbDryWet, state[\reverbDryWet],
				\reverbDur, state[\reverbDur],
				\amp, state[\amp],
			],
			\addToTail
		);
	};

	// GUI
	win = Window(
		"Voxa",
		Rect(
			Window.screenBounds.width * 0.1,
			Window.screenBounds.height * 0.1,
			Window.screenBounds.width * 0.8,
			Window.screenBounds.height * 0.8
		);
	)
	.background_(Color.white)
	.view.onResize_({ resizeFunc.value; });

	stackLayout = StackLayout()
	.mode_(\stackAll);

	style = GMStyle()
	.borderSize_(1)
	.borderColor_(Color(0.75, 0.75, 0.75))
	.secondBorderSize_(1)
	.secondBorderColor_(Color(0.5, 0.5, 0.5))
	.thirdBorderSize_(1)
	.thirdBorderColor_(Color(0.75, 0.75, 0.75))
	.mainColor_(mainColor)
	.backColor_(Color.grey)
	.fontColor_(Color.white)
	.backgroundColor_(Color(0.75, 0.75, 0.75))
	.helpersColor_(Color(1, 1, 1))
	.outlineSize_(2);

	textStyle = style.deepCopy
	.borderSize_(0)
	.secondBorderSize_(0)
	.thirdBorderSize_(0);

	getLabel = { |string|
		GMTextView()
		.maxHeight_(36)
		.fontRatio_(0.5)
		.displayFrame_(true)
		.style_(textStyle)
		.string_(string)
	};

	percentFunc = { |value|
		value = value * 100;
		value = value.trunc(0.01);
		value = value.asString;
		while { value.endsWith("0") } {
			value = value.copyRange(0, value.size - 2);
		};
		if(value.endsWith(".")) {
			value = value.copyRange(0, value.size - 2);
		};
		value = value ++ "%";
		value
	};

	// File View
	loadButton = GMButton()
	.style_(style)
	.maxWidth_(64)
	.svg_((assets ++ "load.svg"))
	.action_({ load.value; });

	saveButton = GMFeedbackButton()
	.style_(style)
	.maxWidth_(64)
	.svg_((assets ++ "save.svg"))
	.action_({ save.value; });

	saveAsButton = GMButton()
	.style_(style)
	.maxWidth_(64)
	.svg_((assets ++ "saveAs.svg"))
	.action_({ saveAs.value; });

	fileView = VLayout()
	.spacing_(margins)
	.margins_(0)
	.add(loadButton)
	.add(saveButton)
	.add(saveAsButton);

	// Title
	title = GMButton()
	.style_(style)
	.svg_((assets ++ "voxa.svg"))
	.svgRatio_(0.8)
	.displayFrame_(false);

	// Inputs GUI
	inputsLayout = HLayout()
	.margins_(0)
	.spacing_(4);

	numInputs.do({ |index|
		var button = GMSwitchButton()
		.style_(style)
		.states_([
			(string: (index + 1).asString, color: Color(0.75, 0.75, 0.75), fontColor: Color.white),
			(string: (index + 1).asString, color: mainColor, fontColor: Color.white)
		])
		.action_({ |state|
			toggleInput.value(index, state);
		});
		inputsLayout.add(button);
		inputsButtons.add(button);
	});

	inputsView = VLayout()
	.margins_(0)
	.spacing_(0)
	.add(
		VLayout()
		.margins_(0)
		.spacing_(margins)
		.add(getLabel.value("inputs"), 1)
		.add(inputsLayout, 4);
	);

	// Filter GUI
	hpButton = GMSwitchButton()
	.style_(style)
	.states_([
		(string: "HPF", color: Color(0.75, 0.75, 0.75), fontColor: Color.white),
		(string: "HPF", color: mainColor, fontColor: Color.white),
	])
	.state_(state[\hpGate])
	.maxWidth_(96)
	.action_({ |state| setHPGate.value(state); });
	hpSlider = GMSymbolSlider()
	.style_(style)
	.orientation_(\horizontal)
	.min_(20)
	.max_(20000)
	.scale_(\exp)
	.value_(state[\hpFreq])
	.displayFunction_({ |value| value.asInteger })
	.fontRatio_(0.5)
	.displayLine_(\none)
	.symbolRatio_(0.666)
	.action_({ |value| setHPFreq.value(value); });

	lpButton = GMSwitchButton()
	.style_(style)
	.states_([
		(string: "LPF", color: Color(0.75, 0.75, 0.75), fontColor: Color.white),
		(string: "LPF", color: mainColor, fontColor: Color.white)
	])
	.state_(state[\hpGate])
	.maxWidth_(96)
	.action_({ |state| setLPGate.value(state); });
	lpSlider = GMSymbolSlider()
	.style_(style)
	.orientation_(\horizontal)
	.min_(20)
	.max_(20000)
	.scale_(\exp)
	.value_(state[\lpFreq])
	.displayFunction_({ |value| value.asInteger })
	.fontRatio_(0.5)
	.displayLine_(\none)
	.symbolRatio_(0.666)
	.action_({ |value| setLPFreq.value(value); });

	brfButton = GMSwitchButton()
	.style_(style)
	.states_([
		(string: "BRF", color: Color(0.75, 0.75, 0.75), fontColor: Color.white),
		(string: "BRF", color: mainColor, fontColor: Color.white)
	])
	.state_(state[\brfGate])
	.maxWidth_(96)
	.action_({ |state| setBRFGate.value(state); });
	brfSlider = GMSymbolSlider()
	.style_(style)
	.orientation_(\horizontal)
	.min_(20)
	.max_(20000)
	.scale_(\exp)
	.value_(state[\brfFreq])
	.displayFunction_({ |value| value.asInteger })
	.fontRatio_(0.5)
	.displayLine_(\none)
	.symbolRatio_(0.666)
	.action_({ |value| setBRFFreq.value(value); });

	filterView = UserView()
	.layout_(
		VLayout()
		.margins_(0)
		.spacing_(margins)
		.add(
			HLayout()
			.margins_(0)
			.spacing_(0)
			.add(hpButton, 1)
			.add(hpSlider, 3)
		)
		.add(
			HLayout()
			.margins_(0)
			.spacing_(0)
			.add(lpButton, 1)
			.add(lpSlider, 3)
		)
		.add(
			HLayout()
			.margins_(0)
			.spacing_(0)
			.add(brfButton, 1)
			.add(brfSlider, 3)
		)
	);

	// Reso GUI
	resoAmountSlider = GMFaderSlider()
	.style_(style)
	.displayHelpers_(true)
	.helpersStyle_(\line)
	.helpersNumber_(5)
	.helperSubdivisions_(3)
	.helpersRatio_(0.333)
	.displayFunction_(percentFunc)
	.centerValue_(false)
	.fontRatio_(0.175)
	.min_(0)
	.max_(0.999)
	.scale_(\log)
	.value_(state[\resoAmount])
	.action_({ |amount| setResoAmount.value(amount); });

	resoNoteSelector = GMSwitchButton()
	.style_(style)
	.states_(notes)
	.maxHeight_(96)
	.action_({ |index| setResoNote.value(index); });

	resoMulSelector = GMSwitchButton()
	.style_(style)
	.maxHeight_(96)
	.states_(["x1", "x2", "x4", "x8"])
	.state_([1, 2, 4, 8].indexOfEqual(state[\resoMul]))
	.action_({ |index| setResoMul.value([1, 2, 4, 8][index]); });

	resoHarmoMixer = GMFaderMultiSlider()
	.style_(style)
	.values_(state[\resoHarmoMix])
	.displayValues_(false)
	.action_({ |values| setResoHarmoMix.value(values); });

	resoHarmoFB = GMFaderMultiSlider()
	.style_(style)
	.values_(state[\resoHarmoFB])
	.displayValues_(false)
	.scale_(\log)
	.action_({ |values| setResoHarmoFB.value(values); });

	resoAmpSlider = GMFaderSlider()
	.style_(style)
	.displayHelpers_(true)
	.helpersStyle_(\line)
	.helpersNumber_(5)
	.helperSubdivisions_(3)
	.helpersRatio_(0.333)
	.displayFunction_(percentFunc)
	.centerValue_(false)
	.fontRatio_(0.175)
	.value_(state[\resoAmp])
	.action_({ |amp| setResoAmp.value(amp); });

	resoView = VLayout()
	.margins_(0)
	.spacing_(margins)
	.add(getLabel.value("resonance"), 1)
	.add(
		HLayout()
		.spacing_(margins)
		.margins_(0)
		.add(
			VLayout()
			.margins_(0)
			.spacing_(margins)
			.add(getLabel.value("freq"), 1)
			.add(
				HLayout()
				.margins_(0)
				.spacing_(margins)
				.add(resoNoteSelector, 1)
				.add(resoMulSelector, 1),
				1
			)
			.add(getLabel.value("harmo amps"), 1)
			.add(resoHarmoMixer, 3)
			.add(getLabel.value("harmo feedbacks"), 1)
			.add(resoHarmoFB, 3),
			2
		)
		.add(
			VLayout()
			.margins_(0)
			.spacing_(margins)
			.add(getLabel.value("feedback"), 1)
			.add(resoAmountSlider, 4),
			1
		)
		.add(
			VLayout()
			.margins_(0)
			.spacing_(margins)
			.add(getLabel.value("amp"), 1)
			.add(resoAmpSlider, 4),
			1
		),
		4
	);

	// Echo GUI
	echoClock = TempoClock().tempo_((60 / state[\echoBPM]));

	playRoutine = {
		echoRoutine = Routine({
			loop {
				echoTapTempo.blink;
				1.wait;
			};
		}).play(echoClock);
	};

	echoAmountSlider = GMFaderSlider()
	.style_(style)
	.displayHelpers_(true)
	.helpersStyle_(\line)
	.helpersNumber_(5)
	.helperSubdivisions_(3)
	.helpersRatio_(0.333)
	.displayFunction_(percentFunc)
	.centerValue_(false)
	.fontRatio_(0.175)
	.value_(state[\echoAmount])
	.action_({ |amount| setEchoAmount.value(amount); });

	echoTapTempo = GMTapTempo()
	.style_(style)
	.bpm_(state[\echoBPM])
	.maxHeight_(96)
	.blinkColor_(mainColor)
	.blinkFontColor_(Color.white)
	.action_({ |bpm|
		if(bpm.notNil) {
			setEchoBPM.value(bpm);
			playRoutine.value;
		} {
			echoRoutine.stop;
		};
	});

	echoMulState = (
		string: "",
		color: Color.white,
		fontColor: Color.black
	);

	echoMulSelector = GMSwitchButton()
	.style_(style)
	.states_([
		echoMulState.deepCopy.put(\svg, assets ++ "r7.svg"),
		echoMulState.deepCopy.put(\svg, assets ++ "r6.svg"),
		echoMulState.deepCopy.put(\svg, assets ++ "r5.svg"),
		echoMulState.deepCopy.put(\svg, assets ++ "r4.svg"),
		echoMulState.deepCopy.put(\svg, assets ++ "r3.svg"),
		echoMulState.deepCopy.put(\svg, assets ++ "r2.svg"),
		echoMulState.deepCopy.put(\svg, assets ++ "r1.svg")
	])
	.maxHeight_(96)
	.state_([(1/4), (1/3), (1/2), 1, 2, 3, 4].indexOfEqual(1))
	.action_({ |index|
		setEchoMul.value(
			[(1/4), (1/3), (1/2), 1, 2, 3, 4][index]
		);
	});

	echoAmpSlider = GMFaderSlider()
	.style_(style)
	.displayHelpers_(true)
	.helpersStyle_(\line)
	.helpersNumber_(5)
	.helperSubdivisions_(3)
	.helpersRatio_(0.333)
	.displayFunction_(percentFunc)
	.centerValue_(false)
	.fontRatio_(0.175)
	.value_(state[\echoAmp])
	.action_({ |amp| setEchoAmp.value(amp); });

	echoView = VLayout()
	.margins_(0)
	.spacing_(margins)
	.add(getLabel.value("echo"), 1)
	.add(
		VLayout()
		.spacing_(margins)
		.margins_(0)
		.add(
			VLayout()
			.spacing_(margins)
			.margins_(0)
			.add(getLabel.value("rythm"), 1)
			.add(
				HLayout()
				.margins_(0)
				.spacing_(margins)
				.add(echoTapTempo, 1)
				.add(echoMulSelector, 1),
				3
			),
			1
		)
		.add(
			HLayout()
			.spacing_(margins)
			.margins_(0)
			.add(
				VLayout()
				.margins_(0)
				.spacing_(margins)
				.add(getLabel.value("feedback"), 1)
				.add(echoAmountSlider, 4)
			)
			.add(
				VLayout()
				.margins_(0)
				.spacing_(margins)
				.add(getLabel.value("amp"), 1)
				.add(echoAmpSlider, 4)
			),
			2
		)
	);

	// Reverb GUI
	reverbDryWetSlider = GMFaderSlider()
	.style_(style)
	.displayHelpers_(true)
	.helpersStyle_(\line)
	.helpersNumber_(5)
	.helperSubdivisions_(3)
	.helpersRatio_(0.333)
	.displayFunction_(percentFunc)
	.centerValue_(false)
	.fontRatio_(0.175)
	.value_(state[\reverbDryWet])
	.action_({ |amount| setReverbAmount.value(amount); });

	reverbDurSlider = GMFaderSlider()
	.style_(style)
	.displayHelpers_(true)
	.helpersStyle_(\line)
	.helpersNumber_(5)
	.helperSubdivisions_(3)
	.helpersRatio_(0.333)
	.displayFunction_({ |value|
		value = value.trunc(0.01);
		value = value.asString;
		value = value ++ "s";
		value
	})
	.centerValue_(false)
	.fontRatio_(0.175)
	.min_(0.25)
	.max_(8)
	.scale_(\exp)
	.value_(state[\reverbDur])
	.action_({ |dur| setReverbDur.value(dur); });

	reverbView = VLayout()
	.margins_(0)
	.spacing_(margins)
	.add(getLabel.value("reverb"), 1)
	.add(
		HLayout()
		.spacing_(margins)
		.margins_(0)
		.add(
			VLayout()
			.margins_(0)
			.spacing_(margins)
			.add(getLabel.value("mix"), 1)
			.add(reverbDryWetSlider, 4)
		)
		.add(
			VLayout()
			.margins_(0)
			.spacing_(margins)
			.add(getLabel.value("duration"), 1)
			.add(reverbDurSlider, 4)
		),
		4
	);

	// Amp GUI
	dryAmpSlider = GMFaderSlider()
	.style_(style)
	.displayHelpers_(true)
	.helpersStyle_(\line)
	.helpersNumber_(5)
	.helperSubdivisions_(3)
	.helpersRatio_(0.333)
	.displayFunction_(percentFunc)
	.centerValue_(false)
	.fontRatio_(0.175)
	.value_(state[\dryAmp])
	.action_({ |amp| setDryAmp.value(amp); });

	dryAmpView =
	VLayout()
	.margins_(0)
	.spacing_(margins)
	.add(getLabel.value("dry amp"), 1)
	.add(dryAmpSlider, 4);

	ampSlider = GMFaderSlider()
	.style_(style)
	.displayHelpers_(true)
	.helpersStyle_(\line)
	.helpersNumber_(5)
	.helperSubdivisions_(3)
	.helpersRatio_(0.333)
	.displayFunction_(percentFunc)
	.centerValue_(false)
	.fontRatio_(0.175)
	.value_(state[\amp])
	.action_({ |amp| setAmp.value(amp); });

	ampView =
	VLayout()
	.margins_(0)
	.spacing_(margins)
	.add(getLabel.value("master amp"), 1)
	.add(ampSlider, 4);

	// File views
	saveText = GMTextView()
	.style_(style)
	.string_("Save preset as:")
	.maxHeight_(96)
	.fontRatio_(0.3)
	.displayFrame_(true);
	closeSaveButton = GMCloseButton()
	.style_(style)
	.maxHeight_(96)
	.action_({ saveOverlay.visible_(false); });
	saveInput = TextField()
	.font_(style.font)
	.align_(\center)
	.maxHeight_(96);
	doSaveButton = GMButton()
	.style_(style)
	.maxHeight_(96)
	.stringRatio_(0.3)
	.string_("save")
	.action_({
		if(saveInput.string != "") {
			var fileName = saveInput.string;
			fileName.replace(" ", "__");
			fileName = fileName ++ ".voxa";
			currentFile = fileName;
			save.value;
		};
		saveOverlay.visible_(false);
	});

	saveView = UserView()
	.background_(Color(0.5, 0.5, 0.5))
	.maxWidth_(700)
	.maxHeight_(((96 * 3) + (margins * 4)))
	.layout_(
		VLayout()
		.margins_(margins)
		.spacing_(margins)
		.add(
			HLayout()
			.spacing_(0)
			.margins_(0)
			.add(saveText, 4)
			.add(closeSaveButton, 1),
			1
		)
		.add(saveInput, 1)
		.add(
			HLayout()
			.margins_(0)
			.spacing_(0)
			.add(UserView(), 1)
			.add(doSaveButton, 1)
			.add(UserView(), 1),
			1
		)
	);

	loadText = GMTextView()
	.style_(style)
	.string_("Load preset:")
	.maxHeight_(96)
	.fontRatio_(0.3)
	.displayFrame_(true);
	closeLoadButton = GMCloseButton()
	.style_(style)
	.maxHeight_(96)
	.action_({ loadOverlay.visible_(false); });
	fileSelector = GMGridButton()
	.style_(style);

	loadView = UserView()
	.background_(Color(0.5, 0.5, 0.5))
	.maxWidth_(700)
	.maxHeight_(((96 * 3) + (margins * 4)))
	.layout_(
		VLayout()
		.margins_(margins)
		.spacing_(margins)
		.add(
			HLayout()
			.spacing_(0)
			.margins_(0)
			.add(loadText, 4)
			.add(closeLoadButton, 1),
			1
		)
		.add(fileSelector, 2)
	);

	// Top level layouts
	saveOverlay = UserView()
	.background_(Color(0, 0, 0, 0.75))
	.visible_(false)
	.layout_(
		HLayout()
		.margins_(0)
		.spacing_(0)
		.add(
			VLayout()
			.margins_(0)
			.spacing_(0)
			.add(saveView)
		);
	);

	loadOverlay = UserView()
	.background_(Color(0, 0, 0, 0.75))
	.visible_(false)
	.layout_(
		HLayout()
		.margins_(0)
		.spacing_(0)
		.add(
			VLayout()
			.margins_(0)
			.spacing_(0)
			.add(loadView)
		);
	);

	mainView = UserView()
	.layout_(
		VLayout()
		.margins_(margins * 3)
		.spacing_(margins * 3)
		.add(
			UserView()
			.maxHeight_(128)
			.layout_(
				HLayout()
				.margins_(0)
				.spacing_(margins * 3)
				.add(fileView, 1)
				.add(title, 1)
				.add(inputsView, 1)
				.add(filterView, 2)
			),
			1
		)
		.add(
			HLayout()
			.margins_(0)
			.spacing_(margins * 3)
			.add(resoView, 4)
			.add(echoView, 2)
			.add(dryAmpView, 1)
			.add(reverbView, 2)
			.add(ampView, 1),
			2
		);
	);

	stackLayout.add(saveOverlay);
	stackLayout.add(loadOverlay);
	stackLayout.add(mainView);
	win.layout_(stackLayout);

	// Functions
	toggleInput = { |index, state|
		if(state == 1) {
			inputs[index] = Synth(
				\voxaIn,
				[
					\inChannel, index,
					\out, masterBus
				],
				voxaGroup,
				\addToHead
			);
		} {
			inputs[index].free;
			inputs[index] = nil;
		};
	};

	resizeFunc = {
		inputsButtons.do({ |button|
			button.maxHeight_(button.bounds.width);
		});
	};

	// State controls
	setHPGate = { |gate|
		master.set(\hpGate, gate);
		hpButton.state_(gate);
		state[\hpGate] = gate;
	};

	setHPFreq = { |freq|
		master.set(\hpFreq, freq);
		hpSlider.value_(freq);
		state[\hpFreq] = freq;
	};

	setLPGate = { |gate|
		master.set(\lpGate, gate);
		lpButton.state_(gate);
		state[\lpGate] = gate;
	};

	setLPFreq = { |freq|
		master.set(\lpFreq, freq);
		lpSlider.value_(freq);
		state[\lpFreq] = freq;
	};

	setBRFGate = { |gate|
		master.set(\brfGate, gate);
		brfButton.state_(gate);
		state[\brfGate] = gate;
	};

	setBRFFreq = { |freq|
		master.set(\brfFreq, freq);
		brfSlider.value_(freq);
		state[\brfFreq] = freq;
	};

	setResoAmount = { |amount|
		master.set(\resDecay, amount);
		resoAmountSlider.value_(amount);
		state[\resoAmount] = amount;
	};

	setResoNote = { |index|
		master.set(\resFreq, (freqs[index] * state[\resoMul]));
		resoNoteSelector.state_(index);
		state[\resoNote] = index;
	};

	setResoMul = { |mul|
		master.set(\resFreq, (freqs[state[\resoNote]] * mul));
		resoMulSelector.state_([1, 2, 4, 8].indexOfEqual(mul));
		state[\resoMul] = mul;
	};

	setResoHarmoMix = { |array|
		master.setn(\resAmps, array);
		resoHarmoMixer.values_(array);
		state[\resoHarmoMix] = array;
	};

	setResoHarmoFB = { |array|
		master.setn(\resFBs, array);
		resoHarmoFB.values_(array);
		state[\resoHarmoFB] = array;
	};

	setResoAmp = { |amp|
		master.set(\resAmp, amp);
		resoAmpSlider.value_(amp);
		state[\resoAmp] = amp;
	};

	setEchoAmount = { |amount|
		master.set(\echoDecay, amount);
		echoAmountSlider.value_(amount);
		state[\echoAmount] = amount;
	};

	setEchoBPM = { |bpm|
		master.set(\echoDur, ((60 / bpm) * state[\echoMul]));
		echoClock.tempo_((state[\echoBPM] / 60));
		state[\echoBPM] = bpm;
	};

	setEchoMul = { |mul|
		master.set(\echoDur, ((60 / state[\echoBPM]) * mul));
		echoMulSelector.state_([(1/4), (1/3), (1/2), 1, 2, 3, 4].indexOfEqual(mul));
		state[\echoMul] = mul;
	};

	setEchoAmp = { |amp|
		master.set(\echoAmp, amp);
		echoAmpSlider.value_(amp);
		state[\echoAmp] = amp;
	};

	setReverbAmount = { |amount|
		master.set(\reverbDryWet, amount);
		reverbDryWetSlider.value_(amount);
		state[\reverbDryWet] = amount;
	};

	setReverbDur = { |dur|
		master.set(\reverbDur, dur);
		reverbDurSlider.value_(dur);
		state[\reverbDur] = dur;
	};

	setDryAmp = { |amp|
		master.set(\dryAmp, amp);
		dryAmpSlider.value_(amp);
		state[\dryAmp] = amp;
	};

	setAmp = { |amp|
		master.set(\amp, amp);
		ampSlider.value_(amp);
		state[\amp] = amp;
	};

	mute = {
		setAmp.value(0);
	};

	// File functions
	save = {
		if(currentFile.notNil) {
			var file = File.open(
				(
					folderName +/+
					"presets" +/+
					currentFile
				).standardizePath,
				"w"
			);
			file.write(state.asCompileString);
			file.close;
		} {
			saveAs.value;
		};
	};

	saveAs = {
		saveInput.string_("");
		saveInput.focus;
		saveOverlay.visible_(true);
	};

	load = {
		var fileList = List(0);
		PathName(folderName ++ "/presets/").files.do({ |path|
			if(path.fileName.endsWith(".voxa"))
			{ fileList.add(path.fileName); };
		});
		if(fileList.size > 0) {
			loadOverlay.visible_(true);
			fileSelector.states_(
				fileList.collect({ |string|
					string = string.replace("__", " ");
					string = string.replace(".voxa", "");
					string
				});
			);
			fileSelector.desindex;
			fileSelector.action_({ |index|
				loadFile.value(fileList[index]);
				loadOverlay.visible = false;
				fileList.clear;
			});
		};
	};

	loadFile = { |file|
		var data = this.executeFile((
			folderName +/+
			"presets" +/+
			file
		));
		setHPGate.value(data[\hpGate]);
		setHPFreq.value(data[\hpFreq]);
		setLPGate.value(data[\lpGate]);
		setLPFreq.value(data[\lpFreq]);
		setBRFGate.value(data[\brfGate]);
		setBRFFreq.value(data[\brfFreq]);
		setResoAmount.value(data[\resoAmount]);
		setResoNote.value(data[\resoNote]);
		setResoMul.value(data[\resoMul]);
		setResoHarmoMix.value(data[\resoHarmoMix]);
		setResoHarmoFB.value(data[\resoHarmoFB]);
		setResoAmp.value(data[\resoAmp]);
		setEchoAmount.value(data[\echoAmount]);
		setEchoBPM.value(data[\echoBPM]);
		setEchoMul.value(data[\echoMul]);
		setEchoAmp.value(data[\echoAmp]);
		setReverbAmount.value(data[\reverbDryWet]);
		setReverbDur.value(data[\reverbDur]);
		setDryAmp.value(data[\dryAmp]);
		setAmp.value(data[\amp]);
		currentFile = file;
	};

	// Misc functions
	quit = {
		masterBus.free;
		if(synthFree.not) {
			master.free;
			inputs.do({ |input|
				if(input.notNil)
				{ input.free; };
			});
		};
	};

	win.onClose_({
		quit.value;
	});

	CmdPeriod.doOnce({
		synthFree = true;
		win.close;
	});

	View.globalKeyDownAction_({ |view, char, mod, unicode|
		// CTRL + F
		if(unicode == 6) {
			if(fullScreen)
			{ win.endFullScreen; }
			{ win.fullScreen; };
			fullScreen = fullScreen.not;
		};
		// ESC
		if(unicode == 27) { win.close; };
		// CHAR KEYS
		if(char == $m) { mute.value; };
	});

	// Preset folder check
	if(File.exists((folderName +/+ "presets/")).not)
	{ File.mkdir((folderName +/+ "presets/")); };

	// Hello World!
	playRoutine.value;
	win.front;
});
)