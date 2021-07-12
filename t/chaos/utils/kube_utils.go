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
	"context"
	"io"
	"time"

	"github.com/chaos-mesh/chaos-mesh/api/v1alpha1"
	"github.com/pkg/errors"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes"
	clientScheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/tools/remotecommand"
	kubectlScheme "k8s.io/kubectl/pkg/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

type ClientSet struct {
	CtrlCli client.Client
	KubeCli *kubernetes.Clientset
}

func InitClientSet() (*ClientSet, error) {
	scheme := runtime.NewScheme()
	v1alpha1.AddToScheme(scheme)
	clientScheme.AddToScheme(scheme)

	restConfig := config.GetConfigOrDie()
	ctrlCli, err := client.New(restConfig, client.Options{Scheme: scheme})
	if err != nil {
		return nil, err
	}
	kubeCli, err := kubernetes.NewForConfig(restConfig)
	if err != nil {
		return nil, err
	}

	return &ClientSet{ctrlCli, kubeCli}, nil
}

func GetPods(cli client.Client, ns string, listOption client.MatchingLabels) ([]corev1.Pod, error) {
	podList := &corev1.PodList{}
	err := cli.List(context.Background(), podList, client.InNamespace(ns), listOption)
	if err != nil {
		return nil, err
	}
	return podList.Items, nil
}

func ExecInPod(cli *kubernetes.Clientset, pod *corev1.Pod, cmd string) (string, error) {
	name := pod.GetName()
	namespace := pod.GetNamespace()
	// only get the first container, no harm for now
	containerName := pod.Spec.Containers[0].Name

	req := cli.CoreV1().RESTClient().Post().
		Resource("pods").
		Name(name).
		Namespace(namespace).
		SubResource("exec")

	req.VersionedParams(&corev1.PodExecOptions{
		Container: containerName,
		Command:   []string{"/bin/sh", "-c", cmd},
		Stdin:     false,
		Stdout:    true,
		Stderr:    true,
		TTY:       false,
	}, kubectlScheme.ParameterCodec)

	var stdout, stderr bytes.Buffer
	exec, err := remotecommand.NewSPDYExecutor(config.GetConfigOrDie(), "POST", req.URL())
	if err != nil {
		return "", errors.Wrapf(err, "error in creating NewSPDYExecutor for pod %s in ns: %s", name, namespace)
	}
	err = exec.Stream(remotecommand.StreamOptions{
		Stdin:  nil,
		Stdout: &stdout,
		Stderr: &stderr,
	})
	if stderr.String() != "" {
		stderror := errors.New(stderr.String())
		return "", errors.Wrapf(stderror, "pod: %s\ncommand: %s", name, cmd)
	}
	if err != nil {
		return "", errors.Wrapf(err, "error in streaming remote command: pod: %s in ns: %s\n command: %s", name, namespace, cmd)
	}
	return stdout.String(), nil
}

// Log print log of pod
func Log(pod *corev1.Pod, c *kubernetes.Clientset, sinceTime time.Time) (string, error) {
	podLogOpts := corev1.PodLogOptions{}
	if !sinceTime.IsZero() {
		podLogOpts.SinceTime = &metav1.Time{Time: sinceTime}
	}

	req := c.CoreV1().Pods(pod.Namespace).GetLogs(pod.Name, &podLogOpts)
	podLogs, err := req.Stream()
	if err != nil {
		return "", errors.Wrapf(err, "failed to open log stream for pod %s/%s", pod.GetNamespace(), pod.GetName())
	}
	defer podLogs.Close()

	buf := new(bytes.Buffer)
	_, err = io.Copy(buf, podLogs)
	if err != nil {
		return "", errors.Wrapf(err, "failed to copy information from podLogs to buf")
	}
	return buf.String(), nil
}
