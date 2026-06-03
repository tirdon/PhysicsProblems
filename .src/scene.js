//
//  scene.js
//  PhysicsProblems
//
//  Created by Thiradon Mueangmo on 2/6/2569 BE.
//

//TODO: write a framework for easily creating interactive physics problems, and use it to create a simple math problem, also callable on swift main() entry point.
//TODO: api
const scene = new exports.scene('#main-canvas');

const string = new exports.line({
	start: 0.i,
	end: disk.center,
	color: 'red'
});

const disk = new exports.circle({
	center: -1.i - 1.j,
	radius: 0.1,
	color: 'blue'
});

disk.addpendComponent({
	hover: 'highlight',
	draggable: 'translate',
	pauseOnHover: true
});

const mg = new exports.arrow({
	start: disk.center,
	end: 0.i - 1.j,
	color: 'green',
	opacity: 0.0
});

const tension = new exports.arrow({
	start: disk.center,
	end: 1.i + 1.j,
	color: 'orange',
	opacity: 0.0
});

const forces = new exports.group([mg, tension]);
forces.onHover(() => {
	mg.opacity = 1.0;
	tension.opacity = 1.0;
});
forces.addpendComponent({
	draggable: 'translate', 	//change only offset but rotate relate to disk also
	copy: 'position'
});

const pendulum = new exports.group([string, disk]);

scene.add(forces);
scene.add(pendulum);
scene.play(
	disk.rotate({
	   pivot: 0.i,
	   angle: 0.5
	}), {
	   playback: 'pingPong',
	   easing: 'easeInOut'
});
