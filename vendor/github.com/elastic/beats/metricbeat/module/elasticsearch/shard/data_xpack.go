// Licensed to Elasticsearch B.V. under one or more contributor
// license agreements. See the NOTICE file distributed with
// this work for additional information regarding copyright
// ownership. Elasticsearch B.V. licenses this file to you under
// the Apache License, Version 2.0 (the "License"); you may
// not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

package shard

import (
	"encoding/json"
	"time"

	"github.com/elastic/beats/libbeat/common"
	"github.com/elastic/beats/metricbeat/helper/elastic"
	"github.com/elastic/beats/metricbeat/mb"
	"github.com/elastic/beats/metricbeat/module/elasticsearch"
)

func eventsMappingXPack(r mb.ReporterV2, m *MetricSet, content []byte) {
	stateData := &stateStruct{}
	err := json.Unmarshal(content, stateData)
	if err != nil {
		return
	}

	// TODO: This is currently needed because the cluser_uuid is `na` in stateData in case not the full state is requested.
	// Will be fixed in: https://github.com/elastic/elasticsearch/pull/30656
	clusterID, err := elasticsearch.GetClusterID(m.HTTP, m.HostData().SanitizedURI+statePath, stateData.MasterNode)
	if err != nil {
		return
	}

	for _, index := range stateData.RoutingTable.Indices {
		for _, shards := range index.Shards {
			for _, shard := range shards {
				event := mb.Event{}
				fields, err := schema.Apply(shard)
				if err != nil {
					continue
				}

				// Handle node field: could be string or null
				err = elasticsearch.PassThruField("node", shard, fields)
				if err != nil {
					continue
				}

				// Handle relocating_node field: could be string or null
				err = elasticsearch.PassThruField("relocating_node", shard, fields)
				if err != nil {
					continue
				}

				event.RootFields = common.MapStr{
					"timestamp":    time.Now(),
					"cluster_uuid": clusterID,
					"interval_ms":  m.Module().Config().Period.Nanoseconds() / 1000 / 1000,
					"type":         "shards",
					"shard":        fields,
					"state_uuid":   stateData.StateID,
				}

				// Build source_node object
				nodeID, ok := shard["node"]
				if !ok {
					continue
				}
				if nodeID != nil { // shard has not been allocated yet
					sourceNode, err := getSourceNode(nodeID.(string), stateData)
					if err != nil {
						continue
					}
					event.RootFields.Put("source_node", sourceNode)
				}

				event.Index = elastic.MakeXPackMonitoringIndexName(elastic.Elasticsearch)

				r.Event(event)

			}
		}
	}
}

func getSourceNode(nodeID string, stateData *stateStruct) (common.MapStr, error) {
	nodeInfo, ok := stateData.Nodes[nodeID]
	if !ok {
		return nil, elastic.MakeErrorForMissingField("nodes."+nodeID, elastic.Elasticsearch)
	}

	return common.MapStr{
		"uuid": nodeID,
		"name": nodeInfo.Name,
	}, nil
}