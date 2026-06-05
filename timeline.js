/**
 * Timeline Controller UI for AnimationClip playback
 * Displays keyframe-based clips, excludes system animations.
 * Receives state from Swift WASM, provides seek/pause controls.
 */

const TIMELINE_COLORS = {
  position: '#38bdf8',
  scale: '#a78bfa',
  rotation: '#f97316',
  delay: '#475569',
  keyframe: '#34d399',
  edge: '#38bdf8',
};

function getTrackColor(keyPath) {
  return TIMELINE_COLORS[keyPath] || '#818cf8';
}

class TimelineUI {
  constructor() {
    this._state = null;
    this._dragging = false;
    this._collapsed = false;
    this._build();
    this._bindEvents();
  }

  _build() {
    // Root container
    this.root = document.createElement('div');
    this.root.id = 'timeline-controller';
    this.root.className = 'timeline-controller';

    // Header row
    const header = document.createElement('div');
    header.className = 'timeline-header';

    // Play/Pause button
    this.playBtn = document.createElement('button');
    this.playBtn.id = 'timeline-play-btn';
    this.playBtn.className = 'timeline-btn timeline-play-btn';
    this.playBtn.innerHTML = `<svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><polygon points="6,4 20,12 6,20"/></svg>`;
    header.appendChild(this.playBtn);

    // Time display
    this.timeDisplay = document.createElement('span');
    this.timeDisplay.id = 'timeline-time';
    this.timeDisplay.className = 'timeline-time';
    this.timeDisplay.textContent = '0.00 / 0.00s';
    header.appendChild(this.timeDisplay);

    // Label
    const label = document.createElement('span');
    label.className = 'timeline-label';
    label.textContent = 'Timeline';
    header.appendChild(label);

    // Collapse toggle
    this.collapseBtn = document.createElement('button');
    this.collapseBtn.className = 'timeline-btn timeline-collapse-btn';
    this.collapseBtn.innerHTML = '▾';
    this.collapseBtn.title = 'Toggle tracks';
    header.appendChild(this.collapseBtn);

    this.root.appendChild(header);

    // Scrubber track
    const scrubberWrap = document.createElement('div');
    scrubberWrap.className = 'timeline-scrubber-wrap';

    this.scrubberTrack = document.createElement('div');
    this.scrubberTrack.id = 'timeline-scrubber';
    this.scrubberTrack.className = 'timeline-scrubber';

    this.scrubberFill = document.createElement('div');
    this.scrubberFill.className = 'timeline-scrubber-fill';
    this.scrubberTrack.appendChild(this.scrubberFill);

    this.playhead = document.createElement('div');
    this.playhead.className = 'timeline-playhead';
    this.scrubberTrack.appendChild(this.playhead);

    // Keyframe diamond markers container
    this.markersContainer = document.createElement('div');
    this.markersContainer.className = 'timeline-markers';
    this.scrubberTrack.appendChild(this.markersContainer);

    // Clip region markers
    this.clipRegions = document.createElement('div');
    this.clipRegions.className = 'timeline-clip-regions';
    this.scrubberTrack.appendChild(this.clipRegions);

    scrubberWrap.appendChild(this.scrubberTrack);
    this.root.appendChild(scrubberWrap);

    // Track list (collapsible)
    this.trackList = document.createElement('div');
    this.trackList.className = 'timeline-tracks';
    this.root.appendChild(this.trackList);

    // Mount
    const container = document.querySelector('.canvas-container');
    if (container) {
      container.appendChild(this.root);
    } else {
      document.body.appendChild(this.root);
    }
  }

  _bindEvents() {
    // Play/pause
    this.playBtn.addEventListener('click', () => {
      const ctrl = window.TimelineController;
      if (ctrl && ctrl.togglePause) ctrl.togglePause();
    });

    // Collapse tracks
    this.collapseBtn.addEventListener('click', () => {
      this._collapsed = !this._collapsed;
      this.trackList.classList.toggle('collapsed', this._collapsed);
      this.collapseBtn.innerHTML = this._collapsed ? '▸' : '▾';
    });

    // Scrubber seek
    const seek = (e) => {
      if (!this._state || this._state.totalDuration <= 0) return;
      const rect = this.scrubberTrack.getBoundingClientRect();
      const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
      const time = ratio * this._state.totalDuration;
      const ctrl = window.TimelineController;
      if (ctrl && ctrl.seek) ctrl.seek(time);
    };

    this.scrubberTrack.addEventListener('pointerdown', (e) => {
      this._dragging = true;
      e.target.setPointerCapture(e.pointerId);
      // Pause during scrub
      const ctrl = window.TimelineController;
      if (ctrl && ctrl.setPaused) ctrl.setPaused(true);
      seek(e);
    });

    this.scrubberTrack.addEventListener('pointermove', (e) => {
      if (!this._dragging) return;
      seek(e);
    });

    this.scrubberTrack.addEventListener('pointerup', () => {
      this._dragging = false;
    });

    this.scrubberTrack.addEventListener('pointerleave', () => {
      this._dragging = false;
    });
  }

  /**
   * Called from Swift each frame with the timeline state.
   * @param {{ clips, totalDuration, currentTime, isPaused }} state
   */
  updateState(state) {
    this._state = state;
    this._render(state);
  }

  _render(state) {
    if (!state) return;

    const { clips, totalDuration, currentTime, isPaused } = state;

    // Time display
    this.timeDisplay.textContent = `${currentTime.toFixed(2)} / ${totalDuration.toFixed(2)}s`;

    // Play/Pause icon
    if (isPaused) {
      this.playBtn.innerHTML = `<svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><polygon points="6,4 20,12 6,20"/></svg>`;
      this.playBtn.title = 'Play';
    } else {
      this.playBtn.innerHTML = `<svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><rect x="5" y="4" width="4" height="16"/><rect x="15" y="4" width="4" height="16"/></svg>`;
      this.playBtn.title = 'Pause';
    }

    // Scrubber fill + playhead
    const ratio = totalDuration > 0 ? Math.min(1, currentTime / totalDuration) : 0;
    this.scrubberFill.style.width = `${ratio * 100}%`;
    this.playhead.style.left = `${ratio * 100}%`;

    // Clip regions + keyframe markers
    this.clipRegions.innerHTML = '';
    this.markersContainer.innerHTML = '';

    if (totalDuration > 0) {
      for (const clip of clips) {
        const leftPct = (clip.startTime / totalDuration) * 100;
        const widthPct = (clip.duration / totalDuration) * 100;

        // Clip region
        const region = document.createElement('div');
        region.className = 'timeline-clip-region' + (clip.isCurrent ? ' active' : '');
        region.style.left = `${leftPct}%`;
        region.style.width = `${widthPct}%`;

        // Use the color of the first track
        const trackColor = clip.tracks.length > 0 ? getTrackColor(clip.tracks[0].keyPath) : '#334155';
        region.style.backgroundColor = trackColor;
        this.clipRegions.appendChild(region);

        // Keyframe diamond markers for each track
        for (const track of clip.tracks) {
          for (const kfTime of track.keyframeTimes) {
            const globalKfTime = clip.startTime + kfTime;
            const markerPct = (globalKfTime / totalDuration) * 100;
            const diamond = document.createElement('div');
            diamond.className = 'timeline-keyframe';
            diamond.style.left = `${markerPct}%`;
            diamond.style.borderColor = getTrackColor(track.keyPath);
            this.markersContainer.appendChild(diamond);
          }
        }
      }
    }

    // Track list
    this._renderTracks(clips);
  }

  _renderTracks(clips) {
    // Only rebuild if clip count changed
    const key = clips.map(c => c.index + ':' + c.tracks.length).join(',');
    if (this._trackKey === key) {
      // Just update active states
      const items = this.trackList.querySelectorAll('.timeline-track-item');
      items.forEach((item, i) => {
        if (i < clips.length) {
          item.classList.toggle('active', clips[i].isCurrent);
        }
      });
      return;
    }
    this._trackKey = key;

    this.trackList.innerHTML = '';
    for (const clip of clips) {
      for (const track of clip.tracks) {
        if (track.keyPath === 'delay') continue; // Skip delay tracks
        const item = document.createElement('div');
        item.className = 'timeline-track-item' + (clip.isCurrent ? ' active' : '');

        const dot = document.createElement('span');
        dot.className = 'timeline-track-dot';
        dot.style.backgroundColor = getTrackColor(track.keyPath);
        item.appendChild(dot);

        const name = document.createElement('span');
        name.className = 'timeline-track-name';
        name.textContent = track.keyPath;
        item.appendChild(name);

        const dur = document.createElement('span');
        dur.className = 'timeline-track-dur';
        dur.textContent = `${track.duration.toFixed(1)}s`;
        item.appendChild(dur);

        this.trackList.appendChild(item);
      }
    }
  }
}

// Auto-initialize when the DOM is ready
let _timelineUI = null;

export function initTimeline() {
  if (_timelineUI) return _timelineUI;
  _timelineUI = new TimelineUI();

  // Patch global TimelineController so Swift can call updateState
  const existing = window.TimelineController || {};
  existing.updateState = (state) => _timelineUI.updateState(state);
  window.TimelineController = existing;

  return _timelineUI;
}

// Auto-init
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initTimeline);
} else {
  initTimeline();
}
