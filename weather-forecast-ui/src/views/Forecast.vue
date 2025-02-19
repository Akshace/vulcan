<template>
  <v-container fill-height :style="{ 'max-width': '1200px' }">
    <v-layout row align-center align-content-center pb-16>
      <v-flex xs12>
        <InteractiveMap :map-center="mapCenter | jsonParse" :selected-layer-source="selectedLayerSource"
          :map-layer-url="mapLayerUrl"></InteractiveMap>
      </v-flex>
      <v-flex xs12>
        <TimeSlider @input="clearMapLayer" v-model="timeRange" :disabled="loading"></TimeSlider>
      </v-flex>
      <v-flex shrink pa-2>
        <v-menu ref="dateMenu" v-model="dateMenu" :close-on-content-click="false" :nudge-right="40"
          transition="scale-transition" offset-y min-width="auto">
          <template v-slot:activator="{ on, attrs }">
            <v-text-field label="Date" v-model="selectedDate" prepend-icon="mdi-calendar" filled rounded readonly
              hide-details v-bind="attrs" v-on="on" :disabled="loading"></v-text-field>
          </template>
          <v-date-picker v-model="selectedDate" @input="dateMenu = false; clearMapLayer()" :disabled="loading">
          </v-date-picker>
        </v-menu>
      </v-flex>
      <v-flex shrink pa-2>
        <v-autocomplete label="Location" v-model="mapCenter" prepend-icon="mdi-map-search" item-text="place"
          item-value="coords" :items="locations" filled rounded hide-details
          :disabled="loading || selectedLayerSource === LayerSource.Satellite" @change="clearMapLayer"></v-autocomplete>
      </v-flex>
      <v-spacer />
      <v-flex pa-2 shrink v-show="selectedLayerSource === LayerSource.Satellite">
        <v-btn-toggle v-model="satelliteParameter" dense :disabled="loading" @change="clearMapLayer">
          <v-tooltip bottom>
            <template v-slot:activator="{ on, attrs }">
              <v-btn :value="SatelliteParameters.Temperature" v-bind="attrs" v-on="on">
                <v-icon>mdi-thermometer</v-icon>
              </v-btn>
            </template>
            <span>Temperature</span>
          </v-tooltip>
          <v-tooltip bottom>
            <template v-slot:activator="{ on, attrs }">
              <v-btn :value="SatelliteParameters.Ozone" v-bind="attrs" v-on="on">
                <v-icon>mdi-smoke</v-icon>
              </v-btn>
            </template>
            <span>Ozone</span>
          </v-tooltip>
          <v-tooltip bottom>
            <template v-slot:activator="{ on, attrs }">
              <v-btn :value="SatelliteParameters.Humidity" v-bind="attrs" v-on="on">
                <v-icon>mdi-water-percent</v-icon>
              </v-btn>
            </template>
            <span>Relative Humidity</span>
          </v-tooltip>
        </v-btn-toggle>
      </v-flex>
      <v-flex pa-2 shrink>
        <v-btn-toggle v-model="selectedLayerSource" dense :disabled="loading" @change="clearMapLayer">
          <v-tooltip bottom>
            <template v-slot:activator="{ on, attrs }">
              <v-btn :value="LayerSource.Satellite" v-bind="attrs" v-on="on">
                <v-icon>mdi-satellite-variant</v-icon>
              </v-btn>
            </template>
            <span>Satellite</span>
          </v-tooltip>
          <v-tooltip bottom>
            <template v-slot:activator="{ on, attrs }">
              <v-btn :value="LayerSource.Radar" v-bind="attrs" v-on="on">
                <v-icon>mdi-radar</v-icon>
              </v-btn>
            </template>
            <span>Radar</span>
          </v-tooltip>
        </v-btn-toggle>
      </v-flex>
      <v-flex shrink>
        <v-btn depressed color="primary" :loading="loading" :disabled="loading" @click="fetch">Fetch</v-btn>
      </v-flex>
    </v-layout>
    </v-container>
</template>

<script>
import { mapActions } from 'vuex';
import { unzip } from 'unzipit';
import InteractiveMap from '../components/InteractiveMap.vue';
import TimeSlider from '../components/TimeSlider.vue';
import {
  CityNames, LayerSource, MapCenter, MAP_LAYER_PLACEHOLDER_URL, SatelliteParameters,
} from '../constants/forecast';
import utils from '../mixins/utils';

export default {
  name: 'Forecast',
  components: {
    InteractiveMap,
    TimeSlider,
  },
  data() {
    return {
      LayerSource,
      SatelliteParameters,
      dateMenu: false,
      selectedDate: new Date().toISOString().slice(0, 10),
      timeRange: [0, 0],
      mapCenter: JSON.stringify(MapCenter.BL),
      selectedLayerSource: LayerSource.Radar,
      satelliteParameter: SatelliteParameters.Temperature,
      mapLayerUrl: MAP_LAYER_PLACEHOLDER_URL,
      animationTracks: [],
      locations: Object.entries(MapCenter)
        .map(([place, coords]) => ({ place: CityNames[place], coords: JSON.stringify(coords) }))
        .sort((a, b) => a.place.localeCompare(b.place)),
      loading: false,
    };
  },
  mixins: [utils],
  methods: {
    ...mapActions(['fetchRadarData', 'fetchSatelliteData']),
    async fetch() {
      this.loading = true;
      try {
        switch (this.selectedLayerSource) {
          case LayerSource.Radar:
            await this.updateRadarLayer();
            break;
          case LayerSource.Satellite:
            await this.updateSatelliteLayer();
            break;
          default:
        }
        this.loading = false;
      } catch (err) {
        console.error(err);
        this.loading = false;
      }
    },
    startAnimation(images) {
      this.clearMapLayer();
      if (!Array.isArray(images) || !images.length) return;
      this.animationTracks.push(...images);
      const sliderTrackEl = this.getSliderEl();
      let sliderProgress = null;
      if (sliderTrackEl) {
        sliderProgress = sliderTrackEl.cloneNode(true);
        if (this.animationTracks.length > 1) {
          // Decrease opacity to show track progress only if more than 1 image exists
          sliderTrackEl.style.opacity = 0.5;
        }
        sliderProgress.className = 'v-slider__track-fill progress';
        sliderTrackEl.parentElement.appendChild(sliderProgress);
      }

      let currentImage = 0;
      this.mapLayerUrl = this.animationTracks[currentImage];
      this.interval = setInterval(() => {
        currentImage = (currentImage + 1) % this.animationTracks.length;
        this.mapLayerUrl = this.animationTracks[currentImage];
        if (sliderTrackEl) {
          const sliderWidth = sliderTrackEl.clientWidth;
          // Fix positioning when transitioning between loading
          sliderProgress.style.left = sliderTrackEl.style.left;
          sliderProgress.style.width = `${(currentImage / this.animationTracks.length)
            * sliderWidth}px`;
        }
      }, 200);
    },
    stopAnimation() {
      if (this.interval) {
        clearInterval(this.interval);
        this.interval = null;
      }
      this.animationTracks.filter((url) => url.startsWith('blob:'))
        .forEach((url) => URL.revokeObjectURL(url));
      const sliderTrackEl = this.getSliderEl();
      if (!sliderTrackEl) return;
      Array.from(sliderTrackEl.parentElement.getElementsByClassName('v-slider__track-fill progress'))
        .forEach((childEl) => {
          sliderTrackEl.parentElement.removeChild(childEl);
        });
      sliderTrackEl.style.opacity = 1;
    },
    clearMapLayer() {
      this.stopAnimation();
      this.mapLayerUrl = MAP_LAYER_PLACEHOLDER_URL;
      this.animationTracks.splice(0, this.animationTracks.length);
    },
    getSliderEl() {
      if (this.loading) {
        return document.getElementsByClassName('v-slider__track-background')[1];
      }
      return document.getElementsByClassName('v-slider__track-fill primary')[0];
    },
    getTimeRange() {
      const [year, month, date] = this.selectedDate.split('-');
      const [startHour, startMinute] = this.minutesTimeString(this.timeRange[0]).split(':');
      const [endHour, endMinute] = this.minutesTimeString(this.timeRange[1]).split(':');
      // Month correction as it seems to start from 0
      const cmonth = parseInt(month, 10) - 1;
      // NOTE: Local datetime will be converted to UTC below
      const startTime = new Date(year, cmonth, date, startHour, startMinute).toISOString();
      const endTime = new Date(year, cmonth, date, endHour, endMinute).toISOString();
      return [startTime, endTime];
    },
    async updateRadarLayer() {
      const [startTime, endTime] = this.getTimeRange();
      const [longitude, latitude] = JSON.parse(this.mapCenter);
      const radarStream = await this.fetchRadarData({
        startTime,
        endTime,
        longitude,
        latitude,
      });
      if (!((radarStream instanceof Blob) && radarStream.type === 'application/x-zip-compressed')) {
        console.info('Unable to process response. Radar data likely does not exist for the provided parameters.');
        return;
      }
      const { entries } = await unzip(radarStream);
      // console.debug(entries);
      const imageBlobs = Object.values(entries)
        .sort((entry1, entry2) => entry1.name.localeCompare(entry2.name))
        .map((entry) => entry.blob());
      const images = (await Promise.all(imageBlobs)).map((blob) => URL.createObjectURL(blob));
      this.startAnimation(images);
    },
    async updateSatelliteLayer() {
      const [startTime, endTime] = this.getTimeRange();
      const satelliteStream = await this.fetchSatelliteData({
        startTime,
        endTime,
        parameter: this.satelliteParameter,
      });
      if (!((satelliteStream instanceof Blob) && satelliteStream.type === 'image/png')) {
        console.info('Unable to process response. Satellite data likely does not exist for the provided parameters.');
        return;
      }
      const imageUrl = URL.createObjectURL(satelliteStream);
      this.startAnimation([imageUrl]);
    },
  },
  filters: {
    jsonParse(value) {
      return JSON.parse(value);
    },
  },
};
</script>
<style>
.v-slider__track-fill.progress {
  background-color: #2e7d32 !important;
  padding: 2px;
}
</style>
