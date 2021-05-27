/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package utils

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gavv/httpexpect/v2"
	. "github.com/onsi/gomega"
)

var (
	token          = "edd1c9f034335f136f87ad84b625c8f1"
	Host           = "http://127.0.0.1:9080"
	HostPrometheus = "http://127.0.0.1:9091"

	ReAPISIXFunc = "restart_apisix"
	ReEtcdFunc   = "restart_etcd_and_apisix"
)

type httpTestCase struct {
	E                 *httpexpect.Expect
	Method            string
	Path              string
	Body              string
	Headers           map[string]string
	ExpectStatus      int
	ExpectBody        string
	ExpectStatusRange httpexpect.StatusRange
}

func caseCheck(tc httpTestCase) *httpexpect.Response {
	e := tc.E
	var req *httpexpect.Request
	switch tc.Method {
	case http.MethodGet:
		req = e.GET(tc.Path)
	case http.MethodPut:
		req = e.PUT(tc.Path)
	case http.MethodDelete:
		req = e.DELETE(tc.Path)
	default:
		panic("invalid HTTP method")
	}

	if req == nil {
		panic("fail to init request")
	}
	for key, val := range tc.Headers {
		req.WithHeader(key, val)
	}
	if tc.Body != "" {
		req.WithText(tc.Body)
	}

	resp := req.Expect()
	if tc.ExpectStatus != 0 {
		resp.Status(tc.ExpectStatus)
	}

	if tc.ExpectStatusRange != 0 {
		resp.StatusRange(tc.ExpectStatusRange)
	}

	if tc.ExpectBody != "" {
		resp.Body().Contains(tc.ExpectBody)
	}

	return resp
}

func SetRoute(e *httpexpect.Expect, expectStatusRange httpexpect.StatusRange) {
	caseCheck(httpTestCase{
		E:       e,
		Method:  http.MethodPut,
		Path:    "/apisix/admin/routes/1",
		Headers: map[string]string{"X-API-KEY": token},
		Body: `{
			 "uri": "/get",
			 "plugins": {
				 "prometheus": {}
			 },
			 "upstream": {
				 "nodes": {
					 "httpbin.default.svc.cluster.local:8000": 1
				 },
				 "type": "roundrobin"
			 }
		 }`,
		ExpectStatusRange: expectStatusRange,
	})
}

func GetRoute(e *httpexpect.Expect, expectStatus int) {
	caseCheck(httpTestCase{
		E:            e,
		Method:       http.MethodGet,
		Path:         "/get",
		ExpectStatus: expectStatus,
	})
}

func GetRouteList(e *httpexpect.Expect, expectStatus int) {
	caseCheck(httpTestCase{
		E:            e,
		Method:       http.MethodGet,
		Path:         "/apisix/admin/routes",
		Headers:      map[string]string{"X-API-KEY": token},
		ExpectStatus: expectStatus,
		ExpectBody:   "httpbin.default.svc.cluster.local",
	})
}

func DeleteRoute(e *httpexpect.Expect) {
	caseCheck(httpTestCase{
		E:       e,
		Method:  http.MethodDelete,
		Path:    "/apisix/admin/routes/1",
		Headers: map[string]string{"X-API-KEY": token},
	})
}

func TestPrometheusEtcdMetric(e *httpexpect.Expect, expectEtcd int) {
	caseCheck(httpTestCase{
		E:          e,
		Method:     http.MethodGet,
		Path:       "/apisix/prometheus/metrics",
		ExpectBody: fmt.Sprintf("apisix_etcd_reachable %d", expectEtcd),
	})
}

// get the first line which contains the key
func getPrometheusMetric(e *httpexpect.Expect, g *WithT, key string) string {
	resp := caseCheck(httpTestCase{
		E:      e,
		Method: http.MethodGet,
		Path:   "/apisix/prometheus/metrics",
	})
	resps := strings.Split(resp.Body().Raw(), "\n")
	var targetLine string
	for _, line := range resps {
		if strings.Contains(line, key) {
			targetLine = line
			break
		}
	}
	targetSlice := strings.Fields(targetLine)
	g.Expect(len(targetSlice) == 2).To(BeTrue())
	return targetSlice[1]
}

func GetIngressBandwidthPerSecond(e *httpexpect.Expect, g *WithT) (float64, float64) {
	key := "apisix_bandwidth{type=\"ingress\","
	bandWidthString := getPrometheusMetric(e, g, key)
	bandWidthStart, err := strconv.ParseFloat(bandWidthString, 64)
	g.Expect(err).To(BeNil())
	// after etcd got killed, it would take longer time to get the metrics
	// so need to calculate the duration
	timeStart := time.Now()

	time.Sleep(5 * time.Second)
	bandWidthString = getPrometheusMetric(e, g, key)
	bandWidthEnd, err := strconv.ParseFloat(bandWidthString, 64)
	g.Expect(err).To(BeNil())
	duration := time.Now().Sub(timeStart)

	return bandWidthEnd - bandWidthStart, duration.Seconds()
}

func RoughCompare(a float64, b float64) bool {
	ratio := a / b
	if ratio < 1.3 && ratio > 0.7 {
		return true
	}
	return false
}

func RestartWithBash(g *WithT, funcName string) {
	cmd := exec.Command("bash", "../utils/setup_chaos_utils.sh", funcName)

	stdoutIn, _ := cmd.StdoutPipe()
	stderrIn, _ := cmd.StderrPipe()

	var errStdout, errStderr error
	var stdoutBuf, stderrBuf bytes.Buffer
	stdout := io.MultiWriter(os.Stdout, &stdoutBuf)
	stderr := io.MultiWriter(os.Stderr, &stderrBuf)

	err := cmd.Start()
	g.Expect(err).To(BeNil())

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		_, errStdout = io.Copy(stdout, stdoutIn)
	}()
	wg.Add(1)
	go func() {
		defer wg.Done()
		_, errStderr = io.Copy(stderr, stderrIn)
	}()
	wg.Wait()

	err = cmd.Wait()
	g.Expect(err).To(BeNil())
	g.Expect(errStdout).To(BeNil())
	g.Expect(errStderr).To(BeNil())
}

type silentPrinter struct {
	logger httpexpect.Logger
}

func NewSilentPrinter(logger httpexpect.Logger) silentPrinter {
	return silentPrinter{logger}
}

// Request implements Printer.Request.
func (p silentPrinter) Request(req *http.Request) {
}

// Response implements Printer.Response.
func (silentPrinter) Response(*http.Response, time.Duration) {
}